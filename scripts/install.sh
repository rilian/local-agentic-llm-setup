#!/usr/bin/env bash
# Local Agentic LLM — MLX + OpenCode setup (Mac Apple Silicon).
#
# Usage (see README.md):
#   ./scripts/install.sh              Full install (includes verify + HF cache cleanup)
#   ./scripts/install.sh --upgrade    Full upgrade + repair stack (~varies)
#   ./scripts/install.sh --upgrade --best-model   Switch to best model for 24 GB if needed
# Optional env:
#   PRIMARY_MODEL=mlx-community/...  Override model (--upgrade)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="${REPO_ROOT}/.venv"
PYTHON="${VENV}/bin/python"
PIP="${VENV}/bin/pip"
SERVE="${REPO_ROOT}/scripts/mlx-serve.sh"

_CLI_MODEL="${PRIMARY_MODEL:-}"
DEFAULT_MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
MLX_HOST="127.0.0.1"
MLX_PORT="8080"
MLX_MAX_TOKENS="8192"
MLX_CHAT_TEMPLATE_ARGS='{"enable_thinking":false}'
MLX_API_BASE="http://${MLX_HOST}:${MLX_PORT}"
SWITCH_BEST_MODEL="${SWITCH_BEST_MODEL:-0}"

if [[ -f "$REPO_ROOT/config/models.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/config/models.env"
fi
PRIMARY_MODEL="${_CLI_MODEL:-${PRIMARY_MODEL:-$DEFAULT_MODEL}}"
if [[ "$PRIMARY_MODEL" != */* ]]; then
  PRIMARY_MODEL="$DEFAULT_MODEL"
fi
if [[ "$MLX_CHAT_TEMPLATE_ARGS" != *'"'* ]]; then
  MLX_CHAT_TEMPLATE_ARGS='{"enable_thinking":false}'
fi

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# MLX helpers
# ---------------------------------------------------------------------------

wait_for_mlx() {
  local i
  for i in {1..60}; do
    curl -sf --max-time 3 "${MLX_API_BASE}/v1/models" >/dev/null 2>&1 && return 0
    sleep 2
  done
  die "MLX API not responding on ${MLX_API_BASE}/v1"
}

ensure_venv() {
  if [[ ! -x "$PYTHON" ]]; then
    log "Creating Python venv at .venv..."
    python3 -m venv "$VENV"
  fi
  log "Installing/upgrading MLX dependencies..."
  "$PIP" install -U pip -q
  "$PIP" install -r "$REPO_ROOT/requirements.txt" -q
  log "mlx-lm $("$PYTHON" -c "import mlx_lm; print(mlx_lm.__version__)" 2>/dev/null || echo unknown)"
}

download_model() {
  local model="$1"
  log "Downloading ${model} (HuggingFace → ~/.cache/huggingface)..."
  "$PYTHON" - "$model" <<'PY'
import sys
from huggingface_hub import snapshot_download
snapshot_download(sys.argv[1])
print("Download complete:", sys.argv[1])
PY
}

# ---------------------------------------------------------------------------
# OpenCode config + shell env
# ---------------------------------------------------------------------------

configure_opencode() {
  local example="$REPO_ROOT/opencode.json.example"
  local target="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
  local model_for_config="$PRIMARY_MODEL"
  local existing=""

  [[ -f "$example" ]] || die "Missing $example"

  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]]; then
    existing="$target"
    cp "$target" "${target}.bak.$(date +%Y%m%d%H%M%S)"
    log "Backed up existing OpenCode config"
  fi

  python3 - "$example" "$target" "$existing" "$model_for_config" "$MLX_API_BASE" <<'PY'
import json, sys
example_path, target_path, existing_path, model_id, api_base = sys.argv[1:6]
with open(example_path) as f:
    cfg = json.load(f)
cfg["model"] = f"mlx/{model_id}"
cfg["provider"]["mlx"]["options"]["baseURL"] = f"{api_base.rstrip('/')}/v1"
cfg["provider"]["mlx"]["options"]["apiKey"] = "not-needed"
if model_id not in cfg["provider"]["mlx"]["models"]:
    cfg["provider"]["mlx"]["models"][model_id] = {
        "name": "Qwen3.5 9B OptiQ 4-bit MLX",
        "tool_call": True,
        "context_length": 32768,
        "max_tokens": 8192,
    }
if existing_path:
    try:
        with open(existing_path) as f:
            old = json.load(f)
        if isinstance(old.get("mcp"), dict) and old["mcp"]:
            cfg["mcp"] = {**cfg.get("mcp", {}), **old["mcp"]}
    except (json.JSONDecodeError, OSError):
        pass
with open(target_path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
  log "OpenCode config → $target (model: mlx/${model_for_config})"
}

install_shell_env() {
  local marker="# local-agentic-llm-setup opencode"
  local zshrc="${HOME}/.zshrc"
  if [[ -f "$zshrc" ]] && grep -qF "$marker" "$zshrc" 2>/dev/null; then
    log "OPENCODE_ENABLE_EXA already in ~/.zshrc"
  else
    cat >> "$zshrc" <<EOF

${marker}
export OPENCODE_ENABLE_EXA=1
# optional: export EXA_API_KEY="your-key"  # https://dashboard.exa.ai/api-keys
EOF
    log "Appended OPENCODE_ENABLE_EXA=1 to ~/.zshrc"
  fi
  export OPENCODE_ENABLE_EXA=1
}

update_models_env() {
  local env_file="$REPO_ROOT/config/models.env"
  cp "$REPO_ROOT/config/models.env.example" "$env_file"
  {
    cat "$env_file"
    echo "PRIMARY_DIGEST=$("$PYTHON" -c "
from huggingface_hub import HfApi
info = HfApi().model_info('${PRIMARY_MODEL}')
print(info.sha or 'unknown')
" 2>/dev/null || echo unknown)"
    echo "MLX_LM_VERSION=$("$PYTHON" -c "import mlx_lm; print(mlx_lm.__version__)" 2>/dev/null || echo unknown)"
    echo "OPENCODE_VERSION=$(opencode --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo unknown)"
    echo "UPGRADED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${env_file}.tmp"
  mv "${env_file}.tmp" "$env_file"
}

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

verify_setup() {
  local fail=0
  ok()   { echo "OK   $*"; }
  fail() { echo "FAIL $*" >&2; fail=1; }
  warn_v() { echo "WARN $*" >&2; }

  if [[ -x "$PYTHON" ]]; then
    ok "Python venv at .venv"
  else
    fail "Python venv missing — run: ./scripts/install.sh"
  fi

  if curl -sf --max-time 5 "${MLX_API_BASE}/v1/models" >/dev/null 2>&1; then
    ok "MLX API responding on ${MLX_API_BASE}/v1"
  else
    fail "MLX API not responding on ${MLX_API_BASE}/v1"
    echo "      Fix: ./scripts/mlx-serve.sh start" >&2
  fi

  if launchctl print "gui/$(id -u)/ai.local.mlx-server" >/dev/null 2>&1; then
    ok "LaunchAgent ai.local.mlx-server loaded"
  else
    fail "LaunchAgent ai.local.mlx-server not loaded"
    echo "      Fix: ./scripts/install.sh --upgrade" >&2
  fi

  if curl -sf --max-time 5 "${MLX_API_BASE}/v1/models" >/dev/null 2>&1; then
    local model_id
    model_id="$(curl -sf "${MLX_API_BASE}/v1/models" | python3 -c "
import json, sys
target = sys.argv[1]
d = json.load(sys.stdin)
ids = [m.get('id','') for m in d.get('data',[])]
print('ok:' + target if target in ids else 'missing')
" "$PRIMARY_MODEL" 2>/dev/null || true)"
    if [[ "$model_id" == "ok:${PRIMARY_MODEL}" ]]; then
      ok "Model available: $PRIMARY_MODEL"
    elif [[ -n "$model_id" ]]; then
      fail "Primary model not in server list: $PRIMARY_MODEL"
    fi
  fi

  if command -v opencode >/dev/null 2>&1; then
    ok "OpenCode $(opencode --version 2>/dev/null | head -1)"
  else
    fail "OpenCode not installed"
  fi

  local oc="${HOME}/.config/opencode/opencode.json"
  if [[ -f "$oc" ]]; then
    local oc_check
    oc_check="$(python3 - "$oc" <<'PY'
import json, sys
path = sys.argv[1]
errors = []
try:
    with open(path) as f:
        c = json.load(f)
except Exception as e:
    print(f"parse_error:{e}")
    sys.exit(0)
if c.get("default_agent") != "build":
    errors.append("default_agent")
mlx = c.get("provider", {}).get("mlx", {})
if mlx.get("options", {}).get("timeout", 0) < 600000:
    errors.append("timeout")
models = mlx.get("models", {})
if not any(m.get("tool_call") for m in models.values() if isinstance(m, dict)):
    errors.append("tool_call")
perms = c.get("permission", {})
for t in ("websearch", "webfetch", "task", "read"):
    if perms.get(t) != "allow":
        errors.append(f"perm.{t}")
print("fail:" + ",".join(errors) if errors else "ok")
PY
)"
    if [[ "$oc_check" == "ok" ]]; then
      ok "OpenCode config: tool_call, permissions, build agent"
    else
      fail "OpenCode config not agent-ready ($oc_check)"
      echo "      Fix: ./scripts/install.sh --upgrade" >&2
    fi
  else
    fail "OpenCode config missing"
    echo "      Fix: ./scripts/install.sh --upgrade" >&2
  fi

  if [[ "${OPENCODE_ENABLE_EXA:-}" == "1" ]] || grep -qF "OPENCODE_ENABLE_EXA=1" "${HOME}/.zshrc" 2>/dev/null; then
    ok "OPENCODE_ENABLE_EXA configured (web search)"
  else
    warn_v "OPENCODE_ENABLE_EXA not set — run: ./scripts/install.sh --upgrade"
  fi

  if [[ "$fail" -eq 0 ]]; then
    log "Agent tool test (~15–60s): read README.md via tool call..."
    local agent_result
    agent_result="$(python3 - "$REPO_ROOT" "$PRIMARY_MODEL" "$MLX_API_BASE" <<'PY' || true
import json, sys, urllib.error, urllib.request
from pathlib import Path

repo = Path(sys.argv[1])
model = sys.argv[2]
api_base = sys.argv[3].rstrip("/")
goal_path = repo / "README.md"

def step(*parts):
    print("      " + " ".join(str(p) for p in parts), file=sys.stderr)

if not goal_path.is_file():
    print("missing:README.md")
    sys.exit(0)

goal_text = goal_path.read_text(encoding="utf-8")
expected_line = goal_text.splitlines()[0].strip()
step("expected heading:", expected_line)

tools = [{
    "type": "function",
    "function": {
        "name": "read",
        "description": "Read a file from the project",
        "parameters": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"],
        },
    },
}]

def chat(messages):
    body = json.dumps({
        "model": model,
        "messages": messages,
        "tools": tools,
        "max_tokens": 256,
    }).encode()
    req = urllib.request.Request(
        f"{api_base}/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        return json.loads(resp.read())

messages = [{
    "role": "user",
    "content": (
        "Use the read tool to read README.md, then reply with ONLY the first line of that file. "
        "Do not guess or invent the content."
    ),
}]

try:
    r1 = chat(messages)
except urllib.error.URLError as e:
    print(f"request_error:{e}")
    sys.exit(0)
except Exception as e:
    print(f"request_error:{e}")
    sys.exit(0)

choice1 = (r1.get("choices") or [{}])[0]
msg = choice1.get("message") or {}
finish1 = choice1.get("finish_reason", "")
tool_calls = msg.get("tool_calls") or []
if not tool_calls:
    step("turn 1 finish:", finish1)
    if msg.get("content"):
        step("turn 1 content:", msg.get("content"))
    print("no_tool_call:model replied without using read tool")
    sys.exit(0)

tc = tool_calls[0]
fn = tc.get("function") or {}
if fn.get("name") != "read":
    print(f"wrong_tool:{fn.get('name')}")
    sys.exit(0)

try:
    args = json.loads(fn.get("arguments") or "{}")
except json.JSONDecodeError:
    print("bad_tool_args")
    sys.exit(0)

path = str(args.get("path", ""))
if "README.md" not in path:
    print(f"wrong_path:{path}")
    sys.exit(0)

step("turn 1 tool:", fn.get("name"), json.dumps(args))
step("turn 1 finish:", finish1)

messages.append(msg)
messages.append({
    "role": "tool",
    "tool_call_id": tc.get("id") or "call_verify",
    "content": goal_text[:4000],
})

try:
    r2 = chat(messages)
except Exception as e:
    print(f"request_error_turn2:{e}")
    sys.exit(0)

choice2 = (r2.get("choices") or [{}])[0]
content = (choice2.get("message") or {}).get("content") or ""
step("turn 2 finish:", choice2.get("finish_reason", ""))
step("turn 2 reply:", content)

if expected_line not in content and "Local Agentic LLM" not in content:
    print(f"bad_response:{content[:160]!r}")
    sys.exit(0)

print("ok")
PY
)"
    if [[ "$agent_result" == "ok" ]]; then
      ok "Agent tool test: read README.md via tool, quoted heading"
    else
      fail "Agent tool test failed (${agent_result:-unknown})"
    fi
  fi

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "All checks passed."
    return 0
  fi
  echo "Some checks failed — try: ./scripts/install.sh --upgrade" >&2
  return 1
}

# ---------------------------------------------------------------------------
# OpenCode CLI
# ---------------------------------------------------------------------------

install_opencode_cli() {
  if command -v opencode >/dev/null 2>&1; then
    log "OpenCode already installed: $(opencode --version 2>/dev/null || true)"
    return 0
  fi
  log "Installing OpenCode..."
  if brew tap anomalyco/tap 2>/dev/null; then
    brew install anomalyco/tap/opencode || {
      log "brew failed; trying curl installer..."
      curl -fsSL https://opencode.ai/install | bash
    }
  else
    curl -fsSL https://opencode.ai/install | bash
  fi
}

# ---------------------------------------------------------------------------
# Cleanup unused HF models
# ---------------------------------------------------------------------------

cleanup_hf_cache() {
  ensure_venv
  log "Removing unused HuggingFace model caches (keeping ${PRIMARY_MODEL})..."
  local removed
  removed="$("$PYTHON" - "$PRIMARY_MODEL" <<'PY' 2>&1 || true
import sys
from huggingface_hub import scan_cache_dir

keep = sys.argv[1].replace("/", "--")
cache = scan_cache_dir()
removed = []
for repo in cache.repos:
    slug = repo.repo_id.replace("/", "--")
    if slug.endswith(keep.split("--", 1)[-1]) or keep in slug:
        continue
    removed.append(repo.repo_id)
    for rev in repo.revisions:
        strategy = cache.delete_revisions(rev.commit_hash)
        strategy.execute()
if removed:
    for repo_id in removed:
        print(repo_id)
PY
)"
  if [[ -n "$removed" ]]; then
    echo "$removed" | sed 's/^/      removed: /'
    log "HF cache cleanup done"
  else
    log "HF cache: nothing to remove"
  fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

apply_stack() {
  chmod +x "$SERVE" "$REPO_ROOT/scripts/loop.sh" 2>/dev/null || true
  PRIMARY_MODEL="$PRIMARY_MODEL" "$SERVE" restart || "$SERVE" start
  configure_opencode
  install_shell_env
  [[ -f "$REPO_ROOT/config/models.env" ]] || cp "$REPO_ROOT/config/models.env.example" "$REPO_ROOT/config/models.env"
  update_models_env
}

cmd_install() {
  command -v brew >/dev/null || die "Homebrew required — https://brew.sh"

  if ! command -v python3 >/dev/null 2>&1; then
    log "Installing Python..."
    brew install python
  fi

  ensure_venv
  download_model "$PRIMARY_MODEL"

  install_opencode_cli
  chmod +x "$SERVE" "$REPO_ROOT/scripts/loop.sh" 2>/dev/null || true

  PRIMARY_MODEL="$PRIMARY_MODEL" "$SERVE" start

  configure_opencode
  install_shell_env

  [[ -f "$REPO_ROOT/config/models.env" ]] || cp "$REPO_ROOT/config/models.env.example" "$REPO_ROOT/config/models.env"
  update_models_env

  cleanup_hf_cache
  log "Verifying..."
  verify_setup || warn "Verification failed — model may still be loading; run: ./scripts/install.sh --upgrade"

  echo ""
  echo "=============================================="
  echo " Setup complete (MLX + OpenCode)"
  echo "=============================================="
  echo "  MLX API:   ${MLX_API_BASE}/v1"
  echo "  Model:     ${PRIMARY_MODEL}"
  echo "  OpenCode:  $(command -v opencode || echo 'not found')"
  echo ""
  echo "  source ~/.zshrc          # load OPENCODE_ENABLE_EXA"
  echo "  ./scripts/mlx-serve.sh status"
  echo "  opencode                 # start terminal agent"
  echo "=============================================="
}

version_line() { "$@" 2>&1 | head -1 | tr -d '\n' || echo "n/a"; }

mlx_version() {
  [[ -x "$PYTHON" ]] && "$PYTHON" -c "
import importlib.metadata as m
try:
    print(m.version('mlx'))
except m.PackageNotFoundError:
    print('not installed')
" 2>/dev/null || echo "not installed"
}

mlx_lm_version() {
  [[ -x "$PYTHON" ]] && "$PYTHON" -c "import mlx_lm; print(mlx_lm.__version__)" 2>/dev/null || echo "not installed"
}

opencode_version() {
  command -v opencode >/dev/null 2>&1 && version_line opencode --version || echo "not installed"
}

pinned_digest() {
  local f="$REPO_ROOT/config/models.env"
  if [[ -f "$f" ]]; then
    local d
    d="$(grep '^PRIMARY_DIGEST=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '\r')"
    [[ -n "$d" ]] && { echo "$d"; return; }
  fi
  echo "unknown"
}

short_digest() {
  local d="$1"
  if [[ "$d" == "unknown" || -z "$d" ]]; then
    echo "unknown"
  else
    echo "${d:0:12}"
  fi
}

print_tool_versions() {
  local heading="${1:-Installed versions}"
  echo "--- ${heading} ---"
  echo "  mlx:        $(mlx_version)"
  echo "  mlx-lm:     $(mlx_lm_version)"
  echo "  OpenCode:   $(opencode_version)"
  echo "  Model:      ${PRIMARY_MODEL}"
  echo "  HF digest:  $(short_digest "$(pinned_digest)")"
  echo ""
}

report_version_change() {
  local name="$1" before="$2" after="$3"
  if [[ "$before" == "$after" ]]; then
    echo "  ${name}:  ${after}  (unchanged)"
  else
    echo "  ${name}:  ${before} → ${after}"
  fi
}

upgrade_python_deps() {
  if [[ ! -x "$PYTHON" ]]; then
    log "Creating Python venv at .venv..."
    python3 -m venv "$VENV"
  fi
  local before_x before_m after_x after_m
  before_x="$(mlx_version)"
  before_m="$(mlx_lm_version)"
  log "Upgrading Python dependencies (mlx, mlx-lm)..."
  "$PIP" install -U pip -q
  "$PIP" install -U -r "$REPO_ROOT/requirements.txt" -q
  after_x="$(mlx_version)"
  after_m="$(mlx_lm_version)"
  report_version_change "mlx" "$before_x" "$after_x"
  report_version_change "mlx-lm" "$before_m" "$after_m"
}

upgrade_opencode() {
  local before after
  before="$(opencode_version)"
  if ! command -v opencode >/dev/null 2>&1; then
    log "OpenCode not installed — installing..."
    install_opencode_cli
    after="$(opencode_version)"
    report_version_change "OpenCode" "$before" "$after"
    return
  fi
  brew tap anomalyco/tap 2>/dev/null || true
  if brew list anomalyco/tap/opencode >/dev/null 2>&1; then
    if brew outdated anomalyco/tap/opencode 2>/dev/null | grep -q .; then
      log "Upgrading OpenCode (Homebrew)..."
      brew upgrade anomalyco/tap/opencode
    else
      log "OpenCode already latest (Homebrew)"
    fi
  else
    log "Upgrading OpenCode (opencode upgrade)..."
    opencode upgrade || warn "opencode upgrade failed"
  fi
  after="$(opencode_version)"
  report_version_change "OpenCode" "$before" "$after"
}

# Query HuggingFace + config/recommended-models.json; may set PRIMARY_MODEL.
# Prints human-readable status on stderr; machine lines on stdout: recommended_id= should_switch=
check_recommended_model() {
  local catalog="$REPO_ROOT/config/recommended-models.json"
  local pinned switch_flag="${SWITCH_BEST_MODEL:-0}"
  pinned="$(pinned_digest)"
  ensure_venv 2>/dev/null || true
  "$PYTHON" - "$catalog" "$PRIMARY_MODEL" "$pinned" "$switch_flag" <<'PY'
import json, sys
from pathlib import Path

catalog_path = Path(sys.argv[1])
current = sys.argv[2]
pinned = sys.argv[3]
auto_switch = sys.argv[4] == "1"

def emit(key, val):
    print(f"{key}={val}")

def step(msg):
    print(f"      {msg}", file=sys.stderr)

try:
    from huggingface_hub import HfApi
except ImportError:
    step("model check skipped (huggingface_hub not installed)")
    emit("recommended_id", current)
    emit("should_switch", "0")
    emit("revision_stale", "0")
    sys.exit(0)

if not catalog_path.is_file():
    step("model check skipped (missing config/recommended-models.json)")
    emit("recommended_id", current)
    emit("should_switch", "0")
    emit("revision_stale", "0")
    sys.exit(0)

catalog = json.loads(catalog_path.read_text())
budget = catalog.get("ram_budget_gb", 12)
models = catalog.get("models", [])
known_ids = {m["id"] for m in models}
fitting = [m for m in models if m.get("ram_gb", 99) <= budget and not m.get("experimental")]
if not fitting:
    fitting = models
best = max(fitting, key=lambda m: m.get("rank", 0))
recommended = best["id"]

api = HfApi()
revision_stale = False
current_sha = ""
current_modified = ""
try:
    info = api.model_info(current)
    current_sha = info.sha or ""
    current_modified = str(info.lastModified or "")
    if pinned and pinned not in ("unknown", "") and current_sha and not current_sha.startswith(pinned[:12]):
        if pinned[:12] != current_sha[:12]:
            revision_stale = True
except Exception as e:
    step(f"could not fetch Hub info for {current}: {e}")

step(f"profile: {catalog.get('profile', 'unknown')} (RAM budget {budget} GB for agent)")
step(f"current:  {current}")
if current_modified:
    step(f"  Hub updated: {current_modified}")
if current_sha:
    step(f"  Hub revision: {current_sha[:12]}")
if pinned and pinned not in ("unknown", ""):
    step(f"  pinned:       {pinned[:12]}" + ("  (stale — re-download on upgrade)" if revision_stale else ""))

rec_label = best.get("label", recommended)
step(f"recommended for this Mac: {recommended}")
step(f"  {rec_label}")

should_switch = recommended != current
if should_switch:
    step(f"  → newer/better option available (rank {best.get('rank', '?')} vs current)")
else:
    if revision_stale:
        step("  same model id — Hub has a newer revision (will re-sync weights)")
    else:
        step("  already the best fit in config/recommended-models.json")

# Hub models in Qwen3.5 OptiQ family not in our catalog
try:
    hub = {m.id for m in api.list_models(author="mlx-community", search="Qwen3.5-OptiQ", limit=50)}
    unknown = sorted(hub - known_ids)
    if unknown:
        step("  new on Hub (not in catalog — update recommended-models.json to rank):")
        for uid in unknown[:5]:
            step(f"    - {uid}")
        if len(unknown) > 5:
            step(f"    ... and {len(unknown) - 5} more")
except Exception:
    pass

if should_switch and auto_switch:
    step("  switching PRIMARY_MODEL (--best-model)")
elif should_switch:
    step("  to switch: ./scripts/install.sh --upgrade --best-model")

emit("recommended_id", recommended)
emit("should_switch", "1" if should_switch else "0")
emit("revision_stale", "1" if revision_stale else "0")
PY
}

apply_model_recommendation() {
  local line recommended="" should_switch="0"
  log "Model check (Hub + config/recommended-models.json)..."
  while IFS= read -r line; do
    case "$line" in
      recommended_id=*) recommended="${line#recommended_id=}" ;;
      should_switch=*) should_switch="${line#should_switch=}" ;;
    esac
  done < <(check_recommended_model)

  if [[ "$should_switch" == "1" && "${SWITCH_BEST_MODEL:-0}" == "1" && -n "$recommended" ]]; then
    if [[ "$PRIMARY_MODEL" != "$recommended" ]]; then
      log "Switching model: $PRIMARY_MODEL → $recommended"
      PRIMARY_MODEL="$recommended"
      _CLI_MODEL="$recommended"
    fi
  fi
}

cmd_upgrade() {
  command -v brew >/dev/null || die "Homebrew required"

  local before_d after_d
  before_d="$(pinned_digest)"

  echo "=============================================="
  echo " Upgrade"
  echo "=============================================="
  print_tool_versions "Before"

  echo "--- Upgrading ---"
  upgrade_python_deps
  upgrade_opencode
  apply_model_recommendation
  log "Refreshing model weights (${PRIMARY_MODEL})..."
  download_model "$PRIMARY_MODEL"

  log "Repairing stack (server, OpenCode, launchd)..."
  apply_stack
  cleanup_hf_cache
  after_d="$(pinned_digest)"
  log "Verifying..."
  verify_setup || warn "Verification failed — run: ./scripts/install.sh --upgrade"

  echo ""
  echo "--- After ---"
  print_tool_versions "Installed versions"
  report_version_change "HF digest" "$(short_digest "$before_d")" "$(short_digest "$after_d")"
  echo "=============================================="
  echo "Upgrade complete."
  echo "=============================================="
}

case "${1:-}" in
  --upgrade)
    shift
    SWITCH_BEST_MODEL=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --best-model) SWITCH_BEST_MODEL=1; shift ;;
        *) die "Unknown option for --upgrade: $1 (try --best-model)" ;;
      esac
    done
    cmd_upgrade
    ;;
  -h|--help)
    sed -n '2,18p' "$0"
    ;;
  "")               cmd_install ;;
  *)                die "Unknown option: $1 (try --help)" ;;
esac
