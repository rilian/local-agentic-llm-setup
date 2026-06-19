#!/usr/bin/env bash
# Local Agentic LLM — Rapid-MLX + OpenCode setup (Mac Apple Silicon).
#
# Usage (see README.md):
#   ./scripts/install.sh              Full install (includes verify + HF cache cleanup)
#   ./scripts/install.sh --upgrade    Full upgrade + repair stack (~varies)
#   ./scripts/install.sh --upgrade --best-model   Switch to best model for 24 GB if needed
# Optional env:
#   PRIMARY_MODEL=mlx-community/...  Override model (--upgrade)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/colors.sh"
VENV="${REPO_ROOT}/.venv"
PYTHON="${VENV}/bin/python"
PIP="${VENV}/bin/pip"
SERVE="${REPO_ROOT}/scripts/mlx-serve.sh"

_CLI_MODEL="${PRIMARY_MODEL:-}"
DEFAULT_MODEL="mlx-community/Qwen3.5-4B-OptiQ-4bit"
MLX_HOST="127.0.0.1"
MLX_PORT="8080"
MLX_MAX_TOKENS="4096"
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

# log, warn, die, ok, fail, section, banner — scripts/colors.sh

# ---------------------------------------------------------------------------
# Rapid-MLX helpers
# ---------------------------------------------------------------------------

wait_for_mlx() {
  local i
  for i in {1..60}; do
    curl -sf --max-time 3 "${MLX_API_BASE}/v1/models" >/dev/null 2>&1 && return 0
    sleep 2
  done
  die "Rapid-MLX API not responding on ${MLX_API_BASE}/v1"
}

ensure_venv() {
  if [[ ! -x "$PYTHON" ]]; then
    log "Creating Python venv at .venv..."
    python3 -m venv "$VENV"
  fi
  log "Installing/upgrading Rapid-MLX and dependencies..."
  "$PIP" install -U pip -q
  "$PIP" install -r "$REPO_ROOT/requirements.txt" -q
  log "rapid-mlx $("$VENV/bin/rapid-mlx" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo unknown)"
}

download_model() {
  local model="$1"
  log "Downloading ${model} (HuggingFace → ~/.cache/huggingface)..."
  "$PYTHON" -u - "$model" <<'PY'
import sys
from huggingface_hub import snapshot_download
from huggingface_hub.utils import enable_progress_bars
from tqdm import tqdm

enable_progress_bars()

class ForcedTqdm(tqdm):
    """Force tqdm progress bars even when stdout is not a TTY."""
    def __init__(self, *args, **kwargs):
        kwargs.setdefault("file", sys.stderr)
        kwargs["disable"] = False
        super().__init__(*args, **kwargs)

snapshot_download(sys.argv[1], max_workers=2, tqdm_class=ForcedTqdm)
print("Download complete:", sys.argv[1], flush=True)
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
    short = model_id.split("/")[-1]
    display = short.replace("-", " ").replace("_", " ") + " (MLX)"
    cfg["provider"]["mlx"]["models"][model_id] = {
        "name": display,
        "tool_call": True,
        "context_length": 32768,
        "max_tokens": 4096,
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
  {
    echo "# Pinned model — written/updated by ./scripts/install.sh"
    echo "# Override: PRIMARY_MODEL=mlx-community/... ./scripts/install.sh --upgrade"
    echo ""
    echo "PRIMARY_MODEL=${PRIMARY_MODEL}"
    echo "PRIMARY_DIGEST=$("$PYTHON" -c "
from huggingface_hub import HfApi
info = HfApi().model_info('${PRIMARY_MODEL}')
print(info.sha or 'unknown')
" 2>/dev/null || echo unknown)"
    echo "RAPID_MLX_VERSION=$("$VENV/bin/rapid-mlx" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo unknown)"
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
  check_fail() { fail "$@"; fail=1; }

  if [[ -x "$PYTHON" ]]; then
    ok "Python venv at .venv"
  else
    check_fail "Python venv missing — run: ./scripts/install.sh"
  fi

  if curl -sf --max-time 5 "${MLX_API_BASE}/v1/models" >/dev/null 2>&1; then
    ok "Rapid-MLX API responding on ${MLX_API_BASE}/v1"
  else
    check_fail "Rapid-MLX API not responding on ${MLX_API_BASE}/v1"
    fix_hint "./scripts/mlx-serve.sh start"
  fi

  if launchctl print "gui/$(id -u)/ai.local.mlx-server" >/dev/null 2>&1; then
    ok "LaunchAgent ai.local.mlx-server loaded"
  else
    check_fail "LaunchAgent ai.local.mlx-server not loaded"
    fix_hint "./scripts/install.sh --upgrade"
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
      check_fail "Primary model not in server list: $PRIMARY_MODEL"
    fi
  fi

  if command -v opencode >/dev/null 2>&1; then
    ok "OpenCode $(opencode --version 2>/dev/null | head -1)"
  else
    check_fail "OpenCode not installed"
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
      check_fail "OpenCode config not agent-ready ($oc_check)"
      fix_hint "./scripts/install.sh --upgrade"
    fi
  else
    check_fail "OpenCode config missing"
    fix_hint "./scripts/install.sh --upgrade"
  fi

  if [[ "${OPENCODE_ENABLE_EXA:-}" == "1" ]] || grep -qF "OPENCODE_ENABLE_EXA=1" "${HOME}/.zshrc" 2>/dev/null; then
    ok "OPENCODE_ENABLE_EXA configured (web search)"
  else
    warn_note "OPENCODE_ENABLE_EXA not set — run: ./scripts/install.sh --upgrade"
  fi

  if [[ "$fail" -eq 0 ]]; then
    log "Agent tool test (~15–60s): read README.md via tool call..."
    local agent_result
    agent_result="$(python3 - "$REPO_ROOT" "$PRIMARY_MODEL" "$MLX_API_BASE" <<'PY' || true
import json, os, sys, urllib.error, urllib.request
from pathlib import Path

repo = Path(sys.argv[1])
model = sys.argv[2]
api_base = sys.argv[3].rstrip("/")
goal_path = repo / "README.md"

def step(msg, tone="dim"):
    reset = os.environ.get("LLM_C_RESET", "")
    key = {"dim": "LLM_C_DIM", "watch": "LLM_C_YELLOW", "info": "LLM_C_CYAN"}.get(tone, "LLM_C_DIM")
    pre = os.environ.get(key, "")
    print(f"{pre}      {msg}{reset}", file=sys.stderr)

if not goal_path.is_file():
    print("missing:README.md")
    sys.exit(0)

goal_text = goal_path.read_text(encoding="utf-8")
expected_line = goal_text.splitlines()[0].strip()
step(f"expected heading: {expected_line}")

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
    step(f"turn 1 finish: {finish1}")
    if msg.get("content"):
        step(f"turn 1 content: {msg.get('content')}")
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

step(f"turn 1 tool: {fn.get('name')} {json.dumps(args)}", "info")
step(f"turn 1 finish: {finish1}")

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
step(f"turn 2 finish: {choice2.get('finish_reason', '')}")
step(f"turn 2 reply: {content}")

if expected_line not in content and "Local Agentic LLM" not in content:
    print(f"bad_response:{content[:160]!r}")
    sys.exit(0)

print("ok")
PY
)"
    if [[ "$agent_result" == "ok" ]]; then
      ok "Agent tool test: read README.md via tool, quoted heading"
    else
      check_fail "Agent tool test failed (${agent_result:-unknown})"
    fi
  fi

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    success_msg "All checks passed."
    return 0
  fi
  error_msg "Some checks failed — try: ./scripts/install.sh --upgrade"
  return 1
}

# ---------------------------------------------------------------------------
# OpenCode CLI
# ---------------------------------------------------------------------------

install_opencode_cli() {
  if opencode_version | grep -qv "not installed"; then
    log "OpenCode already installed: $(opencode_version)"
    return 0
  fi
  log "Installing OpenCode (official installer)..."
  curl -fsSL https://opencode.ai/install | bash
  hash -r 2>/dev/null || true
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
import shutil
from pathlib import Path
from huggingface_hub import scan_cache_dir

keep = sys.argv[1].replace("/", "--")
cache = scan_cache_dir()
removed = []
for repo in cache.repos:
    slug = repo.repo_id.replace("/", "--")
    if slug == keep:
        continue
    removed.append(repo.repo_id)
    for rev in repo.revisions:
        strategy = cache.delete_revisions(rev.commit_hash)
        strategy.execute()
    # Remove empty repo directory if it still exists
    repo_dir = Path(cache.cache_dir) / f"models--{slug}"
    if repo_dir.exists():
        try:
            shutil.rmtree(repo_dir)
        except Exception:
            pass
if removed:
    for repo_id in removed:
        print(repo_id)
PY
)"
  if [[ -n "$removed" ]]; then
    while IFS= read -r line; do
      dim_line "      removed: $line"
    done <<< "$removed"
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
  update_models_env
  "$SERVE" restart || "$SERVE" start
  configure_opencode
  install_shell_env
}

cmd_install() {
  command -v brew >/dev/null || die "Homebrew required — https://brew.sh"

  if ! command -v python3 >/dev/null 2>&1; then
    log "Installing Python..."
    brew install python
  fi

  echo ""
  ensure_venv
  echo ""
  download_model "$PRIMARY_MODEL"

  echo ""
  install_opencode_cli
  chmod +x "$SERVE" "$REPO_ROOT/scripts/loop.sh" 2>/dev/null || true

  echo ""
  PRIMARY_MODEL="$PRIMARY_MODEL" "$SERVE" start

  echo ""
  configure_opencode
  install_shell_env

  [[ -f "$REPO_ROOT/config/models.env" ]] || cp "$REPO_ROOT/config/models.env.example" "$REPO_ROOT/config/models.env"
  echo ""
  update_models_env

  echo ""
  cleanup_hf_cache
  echo ""
  log "Verifying..."
  verify_setup || warn "Verification failed — model may still be loading; run: ./scripts/install.sh --upgrade"

  echo ""
  banner "Setup complete (Rapid-MLX + OpenCode)"
  label_value "Rapid-MLX API" "${MLX_API_BASE}/v1"
  label_value "Model" "${PRIMARY_MODEL}"
  label_value "OpenCode" "$(command -v opencode || echo 'not found')"
  echo ""
  dim_line "  source ~/.zshrc          # load OPENCODE_ENABLE_EXA"
  dim_line "  ./scripts/mlx-serve.sh status"
  dim_line "  opencode                 # start terminal agent"
  printf '%b\n' "${C_CYAN}==============================================${C_RESET}"
}

version_line() { "$@" 2>&1 | head -1 | tr -d '\n' || echo "n/a"; }

rapid_mlx_version() {
  local bin="${VENV}/bin/rapid-mlx"
  [[ -x "$bin" ]] && "$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "not installed"
}

opencode_version() {
  local bin
  # official installer puts binary in ~/.opencode/bin which may not be in the running shell's PATH
  for bin in "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode" "$(command -v opencode 2>/dev/null)"; do
    [[ -x "$bin" ]] && { version_line "$bin" --version; return; }
  done
  echo "not installed"
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
  section "$heading"
  label_value "rapid-mlx" "$(rapid_mlx_version)"
  label_value "OpenCode" "$(opencode_version)"
  label_value "Model" "${PRIMARY_MODEL}"
  label_value "HF digest" "$(short_digest "$(pinned_digest)")"
  echo ""
}

upgrade_python_deps() {
  if [[ ! -x "$PYTHON" ]]; then
    log "Creating Python venv at .venv..."
    python3 -m venv "$VENV"
  fi
  local before_r after_r
  before_r="$(rapid_mlx_version)"
  log "Upgrading Python dependencies (rapid-mlx)..."
  "$PIP" install -U pip -q
  "$PIP" install -U -r "$REPO_ROOT/requirements.txt" -q
  after_r="$(rapid_mlx_version)"
  report_version_change "rapid-mlx" "$before_r" "$after_r"
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
  log "Upgrading OpenCode (latest from GitHub via official installer)..."
  curl -fsSL https://opencode.ai/install | bash || warn "OpenCode upgrade failed"
  hash -r 2>/dev/null || true
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
import json, os, sys
from pathlib import Path

catalog_path = Path(sys.argv[1])
current = sys.argv[2]
pinned = sys.argv[3]
auto_switch = sys.argv[4] == "1"

def emit(key, val):
    print(f"{key}={val}")

def step(msg, tone="dim"):
    reset = os.environ.get("LLM_C_RESET", "")
    key = {"dim": "LLM_C_DIM", "watch": "LLM_C_YELLOW", "info": "LLM_C_CYAN", "action": "LLM_C_MAGENTA"}.get(tone, "LLM_C_DIM")
    pre = os.environ.get(key, "")
    print(f"{pre}      {msg}{reset}", file=sys.stderr)

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

api = HfApi()

def hub_model_exists(model_id):
    try:
        api.model_info(model_id)
        return True
    except Exception as e:
        err = str(e).lower()
        if "404" in err or "not found" in err or "repositorynotfound" in err:
            return False
        step(f"  watch: could not query {model_id}: {e}")
        return False

watch = catalog.get("watch", [])
watch_hits = []
for entry in watch:
    wid = entry.get("hub_id", "")
    if not wid or wid in known_ids:
        continue
    if hub_model_exists(wid):
        watch_hits.append(entry)
        step(f"★ WATCH: {wid} is now on Hub", "watch")
        step(f"  {entry.get('label', wid)}", "watch")
        on_avail = entry.get("on_available")
        if on_avail and on_avail.get("ram_gb", 99) <= budget:
            fitting.append({
                "id": wid,
                "rank": on_avail.get("rank", 0),
                "ram_gb": on_avail.get("ram_gb", 99),
                "label": entry.get("label", wid),
                "from_watch": True,
            })
        elif not on_avail:
            step("    (base weights — wait for mlx-community OptiQ before switching PRIMARY_MODEL)")

best = max(fitting, key=lambda m: m.get("rank", 0))
recommended = best["id"]

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

step(f"profile: {catalog.get('profile', 'unknown')} (RAM budget {budget} GB for agent)", "info")
step(f"current:  {current}", "info")
if current_modified:
    step(f"  Hub updated: {current_modified}")
if current_sha:
    step(f"  Hub revision: {current_sha[:12]}")
if pinned and pinned not in ("unknown", ""):
    step(f"  pinned:       {pinned[:12]}" + ("  (stale — re-download on upgrade)" if revision_stale else ""))

rec_label = best.get("label", recommended)
step(f"recommended for this Mac: {recommended}", "info")
step(f"  {rec_label}")

should_switch = recommended != current
if should_switch:
    step(f"  → newer/better option available (rank {best.get('rank', '?')} vs current)", "action")
else:
    if revision_stale:
        step("  same model id — Hub has a newer revision (will re-sync weights)")
    else:
        step("  already the best fit in config/recommended-models.json")

if watch and not watch_hits:
    step("  watch (not on Hub yet):")
    for entry in watch:
        wid = entry.get("hub_id", "")
        if wid and wid not in known_ids:
            step(f"    - {wid}")

# Hub models in Qwen OptiQ families not in our catalog
try:
    hub = set()
    for search in ("Qwen3.5-OptiQ", "Qwen3.6-OptiQ"):
        hub.update(m.id for m in api.list_models(author="mlx-community", search=search, limit=50))
    unknown = sorted(hub - known_ids - {e.get("hub_id") for e in watch})
    if unknown:
        step("  new on Hub (not in catalog — update recommended-models.json to rank):")
        for uid in unknown:
            step(f"    - {uid}")
except Exception:
    pass

if watch_hits:
    optiq_ready = any(e.get("on_available") for e in watch_hits)
    if optiq_ready and recommended != current:
        step("  watched OptiQ model ready — run: ./scripts/install.sh --upgrade --best-model", "action")
    elif optiq_ready and recommended == current:
        step("  watched OptiQ model ready — add to catalog and re-run upgrade")

if should_switch and auto_switch:
    step("  switching PRIMARY_MODEL (--best-model)")
elif should_switch:
    step("  to switch: ./scripts/install.sh --upgrade --best-model", "action")

emit("recommended_id", recommended)
emit("should_switch", "1" if should_switch else "0")
emit("revision_stale", "1" if revision_stale else "0")
PY
}

apply_model_recommendation() {
  local line recommended="" should_switch="0" revision_stale="0"
  log "Model check (Hub + config/recommended-models.json)..."
  while IFS= read -r line; do
    case "$line" in
      recommended_id=*)  recommended="${line#recommended_id=}" ;;
      should_switch=*)   should_switch="${line#should_switch=}" ;;
      revision_stale=*)  revision_stale="${line#revision_stale=}" ;;
    esac
  done < <(check_recommended_model)
  _REVISION_STALE="$revision_stale"

  if [[ "$should_switch" == "1" && "${SWITCH_BEST_MODEL:-0}" == "1" && -n "$recommended" ]]; then
    if [[ "$PRIMARY_MODEL" != "$recommended" ]]; then
      log "Switching model: $PRIMARY_MODEL → $recommended"
      PRIMARY_MODEL="$recommended"
      _CLI_MODEL="$recommended"
    fi
  fi
}

cmd_upgrade() {
  local before_d after_d model_before
  before_d="$(pinned_digest)"
  model_before="$PRIMARY_MODEL"

  banner "Upgrade"
  print_tool_versions "Before"

  section "Upgrading"
  upgrade_python_deps
  echo ""
  upgrade_opencode
  echo ""

  _REVISION_STALE="0"
  apply_model_recommendation

  # If CLI MODEL was specified, force use it (override recommendation)
  if [[ -n "$_CLI_MODEL" && "$PRIMARY_MODEL" != "$_CLI_MODEL" ]]; then
    log "Forcing model override ($_CLI_MODEL) over recommendation ($PRIMARY_MODEL)"
    PRIMARY_MODEL=$_CLI_MODEL
  fi

  echo ""
  local hf_snapshots="${HOME}/.cache/huggingface/hub/models--${PRIMARY_MODEL//\//--}/snapshots"
  if [[ "$PRIMARY_MODEL" != "$model_before" ]]; then
    log "Downloading new model (${PRIMARY_MODEL})..."
    download_model "$PRIMARY_MODEL"
  elif [[ "${_REVISION_STALE:-0}" == "1" ]]; then
    log "Refreshing model weights (${PRIMARY_MODEL} — Hub has newer revision)..."
    download_model "$PRIMARY_MODEL"
  elif [[ ! -d "$hf_snapshots" ]] || [[ -z "$(ls -A "$hf_snapshots" 2>/dev/null)" ]]; then
    log "Downloading model (not in local cache): ${PRIMARY_MODEL}..."
    download_model "$PRIMARY_MODEL"
  else
    log "Model weights already current — skipping download (${PRIMARY_MODEL})"
  fi

  echo ""
  log "Repairing stack (server, OpenCode, launchd)..."
  apply_stack
  echo ""
  cleanup_hf_cache
  echo ""
  after_d="$(pinned_digest)"
  log "Verifying..."
  verify_setup || warn "Verification failed — run: ./scripts/install.sh --upgrade"

  echo ""
  section "After"
  print_tool_versions "Installed versions"
  report_version_change "HF digest" "$(short_digest "$before_d")" "$(short_digest "$after_d")"
  echo ""
  banner "Upgrade complete"
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
