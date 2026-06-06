#!/usr/bin/env bash
# Local Agentic LLM — MLX + OpenCode setup (Mac Apple Silicon).
#
# Usage (see docs/SETUP.md):
#   ./scripts/install.sh              Full install on a new machine
#   ./scripts/install.sh --verify     Verify setup (~15s)
#   ./scripts/install.sh --repair     Re-apply MLX server + OpenCode config
#   ./scripts/install.sh --upgrade    Upgrade Python deps + OpenCode + model
#   ./scripts/install.sh --upgrade-models  Re-download model weights
#   ./scripts/install.sh --cleanup    Remove unused HF model cache entries
#   ./scripts/install.sh --check      Check for available upgrades (no changes)
# Env vars:
#   PRIMARY_MODEL=mlx-community/Qwen3.5-9B-OptiQ-4bit
#   MLX_PORT=8080
#   MLX_MAX_TOKENS=8192
#   SKIP_MODELS=1                  Upgrade: skip model re-download
#   SKIP_BREW=1                    Upgrade: skip brew upgrades
#   VERIFY_INFERENCE=1             Verify: slow full inference test (~1 min)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="${REPO_ROOT}/.venv"
PYTHON="${VENV}/bin/python"
PIP="${VENV}/bin/pip"
SERVE="${REPO_ROOT}/scripts/mlx-serve.sh"

_CLI_MODEL="${PRIMARY_MODEL:-}"
_CLI_OPENCODE_MODEL="${OPENCODE_MODEL_ID:-}"
MLX_HOST="${MLX_HOST:-127.0.0.1}"
MLX_PORT="${MLX_PORT:-8080}"
MLX_MAX_TOKENS="${MLX_MAX_TOKENS:-8192}"
MLX_CHAT_TEMPLATE_ARGS='{"enable_thinking":false}'
MLX_API_BASE="http://${MLX_HOST}:${MLX_PORT}"
SKIP_MODELS="${SKIP_MODELS:-0}"
SKIP_BREW="${SKIP_BREW:-0}"
VERIFY_INFERENCE="${VERIFY_INFERENCE:-0}"
AGENT_CONTEXT_LENGTH="${AGENT_CONTEXT_LENGTH:-32768}"

if [[ -f "$REPO_ROOT/config/models.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/config/models.env"
fi
PRIMARY_MODEL="${_CLI_MODEL:-${PRIMARY_MODEL:-mlx-community/Qwen3.5-9B-OptiQ-4bit}}"
OPENCODE_MODEL_ID="${_CLI_OPENCODE_MODEL:-${OPENCODE_MODEL_ID:-$PRIMARY_MODEL}}"
if [[ "$PRIMARY_MODEL" != */* ]]; then
  PRIMARY_MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
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
  local model_for_config="${MODEL_FOR_CONFIG:-$OPENCODE_MODEL_ID}"
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
    echo "      Fix: ./scripts/install.sh --repair" >&2
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
      echo "      Fix: ./scripts/install.sh --repair" >&2
    fi
  else
    fail "OpenCode config missing"
    echo "      Fix: ./scripts/install.sh --repair" >&2
  fi

  if [[ "${OPENCODE_ENABLE_EXA:-}" == "1" ]] || grep -qF "OPENCODE_ENABLE_EXA=1" "${HOME}/.zshrc" 2>/dev/null; then
    ok "OPENCODE_ENABLE_EXA configured (web search)"
  else
    warn_v "OPENCODE_ENABLE_EXA not set — run: ./scripts/install.sh --repair"
  fi

  if [[ "$VERIFY_INFERENCE" == "1" ]] && [[ "$fail" -eq 0 ]]; then
    log "Full inference test (~30–90s on first load)..."
    local out
    out="$(curl -sf --max-time 300 "${MLX_API_BASE}/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"${PRIMARY_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: setup ok\"}],\"max_tokens\":64}" \
      2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print((d.get('choices') or [{}])[0].get('message', {}).get('content', ''))
" 2>/dev/null || true)"
    if echo "$out" | grep -qi 'setup ok'; then
      ok "Full inference returned content with 'setup ok'"
    else
      fail "Full inference failed or empty (got: ${out:-empty})"
    fi
  fi

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "All checks passed."
    [[ "$VERIFY_INFERENCE" != "1" ]] && echo "Optional: VERIFY_INFERENCE=1 ./scripts/install.sh --verify"
    return 0
  fi
  echo "Some checks failed — try: ./scripts/install.sh --repair" >&2
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

cmd_cleanup() {
  ensure_venv
  local before after
  before="$(du -sh "${HOME}/.cache/huggingface/hub" 2>/dev/null | awk '{print $1}' || echo unknown)"
  log "HF cache before cleanup: ${before}"
  "$PYTHON" - "$PRIMARY_MODEL" <<'PY'
import os, sys, shutil
from huggingface_hub import scan_cache_dir

keep = sys.argv[1].replace("/", "--")
cache = scan_cache_dir()
for repo in cache.repos:
    slug = repo.repo_id.replace("/", "--")
    if slug.endswith(keep.split("--", 1)[-1]) or keep in slug:
        continue
    print("Removing cached model:", repo.repo_id)
    for rev in repo.revisions:
        strategy = cache.delete_revisions(rev.commit_hash)
        strategy.execute()
PY
  after="$(du -sh "${HOME}/.cache/huggingface/hub" 2>/dev/null | awk '{print $1}' || echo unknown)"
  echo ""
  echo "=============================================="
  echo " Cleanup complete"
  echo "  HF cache: ${before} → ${after}"
  echo "  Keep:     ${PRIMARY_MODEL}"
  echo "=============================================="
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

cmd_repair() {
  command -v brew >/dev/null || die "Homebrew required"
  ensure_venv
  chmod +x "$SERVE"
  PRIMARY_MODEL="$PRIMARY_MODEL" MLX_PORT="$MLX_PORT" "$SERVE" restart || "$SERVE" start
  export MODEL_FOR_CONFIG="$OPENCODE_MODEL_ID"
  configure_opencode
  install_shell_env
  update_models_env
  verify_setup
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

  PRIMARY_MODEL="$PRIMARY_MODEL" MLX_PORT="$MLX_PORT" "$SERVE" start

  export MODEL_FOR_CONFIG="$OPENCODE_MODEL_ID"
  configure_opencode
  install_shell_env

  [[ -f "$REPO_ROOT/config/models.env" ]] || cp "$REPO_ROOT/config/models.env.example" "$REPO_ROOT/config/models.env"
  update_models_env

  log "Verifying..."
  verify_setup || warn "Verification failed — model may still be loading; run: ./scripts/install.sh --verify"

  echo ""
  echo "=============================================="
  echo " Setup complete (MLX + OpenCode)"
  echo "=============================================="
  echo "  MLX API:   ${MLX_API_BASE}/v1"
  echo "  Model:     ${PRIMARY_MODEL}"
  echo "  OpenCode:  $(command -v opencode || echo 'not found')"
  echo ""
  echo "  source ~/.zshrc          # load OPENCODE_ENABLE_EXA"
  echo "  ./scripts/install.sh --verify"
  echo "  ./scripts/mlx-serve.sh status"
  echo "  opencode                 # start terminal agent"
  echo "=============================================="
}

version_line() { "$@" 2>&1 | head -1 | tr -d '\n' || echo "n/a"; }

cmd_check_upgrades() {
  command -v brew >/dev/null || die "Homebrew required"
  local env_file="$REPO_ROOT/config/models.env"
  echo "=== Upgrade check (no changes) ==="
  echo ""
  echo "--- Tools ---"
  echo "  mlx-lm:    $( [[ -x "$PYTHON" ]] && "$PYTHON" -c "import mlx_lm; print(mlx_lm.__version__)" 2>/dev/null || echo not installed)"
  echo "  OpenCode:  $(version_line opencode --version)"
  echo ""
  if [[ -x "$PIP" ]]; then
    echo "--- Python packages (outdated) ---"
    "$PIP" list --outdated 2>/dev/null | tail -n +3 | head -10 || echo "  (none or venv missing)"
  fi
  echo ""
  echo "--- Model ---"
  echo "  PRIMARY: ${PRIMARY_MODEL}"
  if [[ -f "$env_file" ]]; then
    grep -E '^(PRIMARY_DIGEST|UPGRADED_AT)=' "$env_file" 2>/dev/null | sed 's/^/  /' || true
  fi
  echo ""
  echo "  HF repo: https://huggingface.co/${PRIMARY_MODEL}"
  echo ""
  echo "Commands:"
  echo "  ./scripts/install.sh --upgrade"
  echo "  ./scripts/install.sh --upgrade-models"
  echo "  See docs/UPGRADING.md · docs/MODELS.md"
}

cmd_upgrade_models() {
  ensure_venv
  download_model "$PRIMARY_MODEL"
  PRIMARY_MODEL="$PRIMARY_MODEL" "$SERVE" restart
  update_models_env
  verify_setup || warn "Verification failed"
  echo "Model upgrade complete: ${PRIMARY_MODEL}"
}

cmd_upgrade() {
  command -v brew >/dev/null || die "Homebrew required"

  local before_c before_m
  before_c="$(version_line opencode --version)"
  before_m="$( [[ -x "$PYTHON" ]] && "$PYTHON" -c "import mlx_lm; print(mlx_lm.__version__)" 2>/dev/null || echo n/a)"

  if [[ "$SKIP_BREW" != "1" ]]; then
    brew tap anomalyco/tap 2>/dev/null || true
    if brew list anomalyco/tap/opencode >/dev/null 2>&1 && brew outdated anomalyco/tap/opencode 2>/dev/null | grep -q .; then
      log "Upgrading opencode..."
      brew upgrade anomalyco/tap/opencode
    fi
    if command -v opencode >/dev/null && ! brew list anomalyco/tap/opencode >/dev/null 2>&1; then
      opencode upgrade || warn "opencode upgrade failed"
    fi
  fi

  ensure_venv
  [[ "$SKIP_MODELS" != "1" ]] && download_model "$PRIMARY_MODEL"
  PRIMARY_MODEL="$PRIMARY_MODEL" "$SERVE" restart

  export MODEL_FOR_CONFIG="$OPENCODE_MODEL_ID"
  configure_opencode
  install_shell_env
  update_models_env
  verify_setup || warn "Verification failed — run: ./scripts/install.sh --repair"

  echo ""
  echo "=============================================="
  echo " Upgrade complete"
  echo "  mlx-lm:    $before_m → $( [[ -x "$PYTHON" ]] && "$PYTHON" -c "import mlx_lm; print(mlx_lm.__version__)" 2>/dev/null || echo n/a)"
  echo "  OpenCode:  $before_c → $(version_line opencode --version)"
  echo "=============================================="
}

case "${1:-}" in
  --verify)         verify_setup ;;
  --repair)         cmd_repair ;;
  --upgrade)        cmd_upgrade ;;
  --upgrade-models) cmd_upgrade_models ;;
  --check)          cmd_check_upgrades ;;
  --cleanup)        cmd_cleanup ;;
  -h|--help)
    sed -n '2,18p' "$0"
    ;;
  "")               cmd_install ;;
  *)                die "Unknown option: $1 (try --help)" ;;
esac
