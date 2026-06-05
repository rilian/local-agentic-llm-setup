#!/usr/bin/env bash
# Local Agentic LLM — single setup entry point (Mac, Homebrew + Ollama + OpenCode).
#
# Usage (see docs/SETUP.md):
#   ./scripts/install.sh              Full install on a new machine
#   ./scripts/install.sh --verify     Verify setup (~15s, no model load)
#   ./scripts/install.sh --upgrade      Upgrade tools + models + re-apply fixes
#   ./scripts/install.sh --upgrade-models  Re-pull Qwen models only (see docs/UPGRADING.md)
#   ./scripts/install.sh --check        Check for available upgrades (no changes)
#   ./scripts/install.sh --repair       Re-apply fixes only (llama-server, context, config)
#
# Env vars (install / upgrade):
#   PRIMARY_MODEL=qwen3-coder:30b
#   SKIP_FAST=1        Skip pulling FAST_MODEL (qwen3-coder:14b)
#   CREATE_64K=1         Optional: create qwen3-coder-64k Modelfile (65536 — tight on 24 GB RAM)
#   SKIP_MODELS=1        Upgrade: skip ollama pull
#   SKIP_BREW=1          Upgrade: skip brew upgrades
#   OLLAMA_CONTEXT=32768 Context length (default 32768)
#   OLLAMA_KEEP_ALIVE=-1  Keep model loaded (-1 = never unload; default -1)
#   VERIFY_INFERENCE=1   Verify: slow full inference test (~2 min)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PRIMARY_MODEL="${PRIMARY_MODEL:-qwen3-coder:30b}"
FAST_MODEL="${FAST_MODEL:-qwen3-coder:14b}"
# Official library has no qwen3-coder:14b — pull community build, alias locally
FAST_MODEL_SOURCE="${FAST_MODEL_SOURCE:-freehuntx/qwen3-coder:14b}"
CONTEXT_MODEL="${CONTEXT_MODEL:-qwen3-coder-64k}"
PULL_FAST="${PULL_FAST:-}"  # deprecated alias for SKIP_FAST=0
SKIP_FAST="${SKIP_FAST:-0}"
CREATE_64K="${CREATE_64K:-0}"
SKIP_MODELS="${SKIP_MODELS:-0}"
SKIP_BREW="${SKIP_BREW:-0}"
OLLAMA_CONTEXT="${OLLAMA_CONTEXT:-32768}"
OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:--1}"
VERIFY_INFERENCE="${VERIFY_INFERENCE:-0}"
MIN_CONTEXT="${MIN_CONTEXT:-32768}"

if [[ -f "$REPO_ROOT/config/models.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/config/models.env"
fi

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Ollama helpers
# ---------------------------------------------------------------------------

wait_for_ollama() {
  for _ in {1..30}; do
    curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && return 0
    sleep 1
  done
  die "Ollama API not responding on :11434"
}

llama_server_target() {
  local brew_prefix ollama_ver
  brew_prefix="$(brew --prefix)"
  ollama_ver="$(ollama --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  echo "${brew_prefix}/Cellar/ollama/${ollama_ver}/libexec/lib/ollama/llama-server"
}

llama_server_resolves() {
  local target
  target="$(llama_server_target)"
  [[ -x "$target" ]] && return 0
  [[ -L "$target" ]] && command -v llama-server >/dev/null && [[ -x "$(command -v llama-server)" ]]
}

fix_llama_server() {
  local target
  target="$(llama_server_target)"

  if ! command -v llama-server >/dev/null 2>&1 || ! llama_server_resolves; then
    log "Installing llama.cpp (Homebrew Ollama needs llama-server for GGUF)..."
    brew install llama.cpp
    mkdir -p "$(dirname "$target")"
    ln -sf "$(command -v llama-server)" "$target"
    log "Linked llama-server → $target"
  else
    log "llama-server OK at $target"
  fi

  log "Restarting Ollama..."
  brew services restart ollama
  wait_for_ollama

  llama_server_resolves || die "llama-server still not usable at $target"
}

fix_ollama_context() {
  local ctx="${1:-$OLLAMA_CONTEXT}"
  local keep_alive="${2:-$OLLAMA_KEEP_ALIVE}"
  local plist="${HOME}/Library/LaunchAgents/homebrew.mxcl.ollama.plist"

  [[ -f "$plist" ]] || die "Ollama plist not found — install Ollama via Homebrew first"

  set_plist_env() {
    local key="$1" value="$2"
    if /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$key" "$plist" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:$key $value" "$plist"
    else
      /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:$key string $value" "$plist"
    fi
  }

  apply_ollama_env() {
    set_plist_env OLLAMA_CONTEXT_LENGTH "$ctx"
    set_plist_env OLLAMA_KEEP_ALIVE "$keep_alive"
  }

  reload_ollama_service() {
    launchctl bootout "gui/$(id -u)/homebrew.mxcl.ollama" 2>/dev/null || \
      launchctl unload "$plist" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || \
      launchctl load "$plist"
  }

  log "Setting OLLAMA_CONTEXT_LENGTH=$ctx OLLAMA_KEEP_ALIVE=$keep_alive"
  apply_ollama_env
  brew services restart ollama
  log "Re-applying env (brew restart resets plist)..."
  apply_ollama_env
  reload_ollama_service
  wait_for_ollama

  local actual_ctx actual_keep
  actual_ctx="$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:OLLAMA_CONTEXT_LENGTH" "$plist" 2>/dev/null || echo "")"
  actual_keep="$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:OLLAMA_KEEP_ALIVE" "$plist" 2>/dev/null || echo "")"
  [[ "$actual_ctx" == "$ctx" ]] || die "OLLAMA_CONTEXT_LENGTH not persisted (got: ${actual_ctx:-unset})"
  [[ "$actual_keep" == "$keep_alive" ]] || die "OLLAMA_KEEP_ALIVE not persisted (got: ${actual_keep:-unset})"
  log "OLLAMA_CONTEXT_LENGTH=$ctx OLLAMA_KEEP_ALIVE=$keep_alive verified"
}

ensure_ollama_post_install() {
  fix_llama_server
  fix_ollama_context "$OLLAMA_CONTEXT"
}

# ---------------------------------------------------------------------------
# OpenCode config + shell env
# ---------------------------------------------------------------------------

configure_opencode() {
  local example="$REPO_ROOT/opencode.json.example"
  local target="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
  local model_for_config="${MODEL_FOR_CONFIG:-$PRIMARY_MODEL}"
  local existing=""

  [[ -f "$example" ]] || die "Missing $example"

  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]]; then
    existing="$target"
    cp "$target" "${target}.bak.$(date +%Y%m%d%H%M%S)"
    log "Backed up existing OpenCode config"
  fi

  python3 - "$example" "$target" "$existing" "$model_for_config" <<'PY'
import json, sys
example_path, target_path, existing_path, model_for_config = sys.argv[1:5]
with open(example_path) as f:
    cfg = json.load(f)
if model_for_config == "qwen3-coder-64k":
    cfg["model"] = "ollama/qwen3-coder-64k"
else:
    cfg["model"] = f"ollama/{model_for_config}"
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
  log "OpenCode config → $target (model: ollama/${model_for_config})"
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

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

pull_models() {
  # PULL_FAST=1 kept for backwards compat
  [[ "$PULL_FAST" == "1" ]] && SKIP_FAST=0

  log "Pulling $PRIMARY_MODEL (may take ~20–30 min)..."
  ollama pull "$PRIMARY_MODEL"
  if [[ "$SKIP_FAST" != "1" ]]; then
    log "Pulling fast model from $FAST_MODEL_SOURCE (~9 GB)..."
    ollama pull "$FAST_MODEL_SOURCE"
    if [[ "$FAST_MODEL" != "$FAST_MODEL_SOURCE" ]]; then
      log "Creating local alias $FAST_MODEL → $FAST_MODEL_SOURCE"
      ollama cp "$FAST_MODEL_SOURCE" "$FAST_MODEL"
    fi
  fi
}

create_64k_variant() {
  log "Creating $CONTEXT_MODEL (64k Modelfile)..."
  cat > /tmp/Modelfile.local-agent <<EOF
FROM $PRIMARY_MODEL
PARAMETER num_ctx 65536
EOF
  ollama create "$CONTEXT_MODEL" -f /tmp/Modelfile.local-agent
}

update_models_env() {
  local env_file="$REPO_ROOT/config/models.env"
  local tmp digest_primary digest_fast digest_fast_src
  tmp="$(mktemp)"
  model_digest() {
    ollama list 2>/dev/null | awk -v m="$1" '$1 == m { print $2; exit }'
  }
  digest_primary="$(model_digest "$PRIMARY_MODEL")"
  digest_fast="$(model_digest "$FAST_MODEL")"
  digest_fast_src="$(model_digest "$FAST_MODEL_SOURCE")"
  if [[ -f "$env_file" ]]; then
    grep -vE '^(OLLAMA_VERSION|OPENCODE_VERSION|LLAMA_CPP_VERSION|UPGRADED_AT|PRIMARY_DIGEST|FAST_DIGEST|FAST_SOURCE_DIGEST)=' "$env_file" > "$tmp" || true
  else
    cp "$REPO_ROOT/config/models.env.example" "$tmp" 2>/dev/null || : > "$tmp"
  fi
  {
    cat "$tmp"
    echo "PRIMARY_DIGEST=${digest_primary:-unknown}"
    echo "FAST_DIGEST=${digest_fast:-unknown}"
    echo "FAST_SOURCE_DIGEST=${digest_fast_src:-unknown}"
    echo "OLLAMA_VERSION=$(ollama --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo unknown)"
    echo "OPENCODE_VERSION=$(opencode --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo unknown)"
    echo "LLAMA_CPP_VERSION=$(brew list --versions llama.cpp 2>/dev/null | awk '{print $2}' || echo unknown)"
    echo "UPGRADED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$env_file"
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

verify_setup() {
  local fail=0
  ok()   { echo "OK   $*"; }
  fail() { echo "FAIL $*" >&2; fail=1; }
  warn() { echo "WARN $*" >&2; }

  if curl -sf --max-time 5 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    ok "Ollama API responding on :11434"
  else
    fail "Ollama API not responding"
  fi

  if command -v ollama >/dev/null && command -v brew >/dev/null; then
    local target
    target="$(llama_server_target)"
    if llama_server_resolves; then
      ok "llama-server present at $target"
    else
      fail "llama-server missing at $target"
      echo "      Fix: ./scripts/install.sh --repair" >&2
    fi
  fi

  local plist="${HOME}/Library/LaunchAgents/homebrew.mxcl.ollama.plist"
  if [[ -f "$plist" ]]; then
    local ctx
    ctx="$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:OLLAMA_CONTEXT_LENGTH" "$plist" 2>/dev/null || echo "")"
    if [[ -n "$ctx" ]] && [[ "$ctx" -ge "$MIN_CONTEXT" ]] 2>/dev/null; then
      ok "OLLAMA_CONTEXT_LENGTH=$ctx"
    else
      fail "OLLAMA_CONTEXT_LENGTH missing or < $MIN_CONTEXT (got: ${ctx:-unset})"
      echo "      Fix: ./scripts/install.sh --repair" >&2
    fi
    local keep
    keep="$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:OLLAMA_KEEP_ALIVE" "$plist" 2>/dev/null || echo "")"
    if [[ "$keep" == "${OLLAMA_KEEP_ALIVE:--1}" ]]; then
      ok "OLLAMA_KEEP_ALIVE=$keep"
    else
      fail "OLLAMA_KEEP_ALIVE missing or wrong (got: ${keep:-unset}, want: ${OLLAMA_KEEP_ALIVE:--1})"
      echo "      Fix: ./scripts/install.sh --repair" >&2
    fi
  else
    fail "Ollama launchd plist not found"
  fi

  if ollama ps 2>/dev/null | tail -n +2 | grep -q .; then
    local run_ctx
    run_ctx="$(ollama ps 2>/dev/null | awk 'NR==2 {print $7}' | tr -dc '0-9')"
    if [[ -n "$run_ctx" ]] && [[ "$run_ctx" -lt "$MIN_CONTEXT" ]]; then
      fail "Loaded model CONTEXT=$run_ctx (need >= $MIN_CONTEXT)"
    elif [[ -n "$run_ctx" ]]; then
      ok "Loaded model CONTEXT=$run_ctx"
    fi
  fi

  local models
  models="$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
  if [[ -n "$models" ]]; then
    ok "Models: $models"
    if ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -qxF "$PRIMARY_MODEL"; then
      ok "Primary model: $PRIMARY_MODEL"
    else
      fail "Primary model missing: $PRIMARY_MODEL"
    fi
    if [[ "$SKIP_FAST" != "1" ]] && ! ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -qxF "$FAST_MODEL"; then
      fail "Fast model missing: $FAST_MODEL (run: ollama pull $FAST_MODEL)"
    elif ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -qxF "$FAST_MODEL"; then
      ok "Fast model: $FAST_MODEL"
    fi
  else
    fail "No models installed"
  fi

  if curl -sf --max-time 5 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    local probe
    probe="$(curl -s --max-time 10 http://127.0.0.1:11434/api/generate \
      -d "{\"model\":\"${PRIMARY_MODEL}\",\"prompt\":\"x\",\"stream\":false}" 2>&1 || true)"
    if echo "$probe" | grep -q 'llama-server binary not found'; then
      fail "Ollama runtime: llama-server not found"
      echo "      Fix: ./scripts/install.sh --repair" >&2
    elif echo "$probe" | grep -q '"response"'; then
      ok "Ollama inference probe (model loaded)"
    else
      ok "Ollama inference probe OK (first load ~2 min)"
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
ollama = c.get("provider", {}).get("ollama", {})
if ollama.get("options", {}).get("timeout", 0) < 600000:
    errors.append("timeout")
models = ollama.get("models", {})
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
    warn "OPENCODE_ENABLE_EXA not set — run: ./scripts/install.sh --repair"
  fi

  if [[ "$VERIFY_INFERENCE" == "1" ]] && [[ "$fail" -eq 0 ]]; then
    log "Full inference test (~2 min)..."
    local out
    out="$(curl -sf --max-time 180 http://127.0.0.1:11434/api/generate \
      -d "{\"model\":\"${PRIMARY_MODEL}\",\"prompt\":\"Reply with exactly: setup ok\",\"stream\":false}" \
      | grep -o 'setup ok' || true)"
    if [[ "$out" == "setup ok" ]]; then
      ok "Full inference returned 'setup ok'"
    else
      fail "Full inference timeout"
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
# Install OpenCode CLI
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
# Modes
# ---------------------------------------------------------------------------

cmd_repair() {
  command -v brew >/dev/null || die "Homebrew required"
  command -v ollama >/dev/null || die "Ollama not installed — run: ./scripts/install.sh"
  brew services start ollama 2>/dev/null || true
  ensure_ollama_post_install
  export MODEL_FOR_CONFIG="${MODEL_FOR_CONFIG:-$PRIMARY_MODEL}"
  configure_opencode
  install_shell_env
  verify_setup
}

cmd_install() {
  command -v brew >/dev/null || die "Homebrew required — https://brew.sh"

  if ! command -v node >/dev/null 2>&1; then
    log "Installing Node.js..."
    brew install node
  fi

  if ! command -v ollama >/dev/null 2>&1; then
    log "Installing Ollama..."
    brew install ollama
  fi

  brew services start ollama
  wait_for_ollama
  ensure_ollama_post_install

  pull_models

  local model_for_config="$PRIMARY_MODEL"
  if [[ "$CREATE_64K" == "1" ]]; then
    create_64k_variant
    model_for_config="$CONTEXT_MODEL"
  fi

  install_opencode_cli
  export MODEL_FOR_CONFIG="$model_for_config"
  configure_opencode
  install_shell_env

  [[ -f "$REPO_ROOT/config/models.env" ]] || cp "$REPO_ROOT/config/models.env.example" "$REPO_ROOT/config/models.env"
  chmod +x "$REPO_ROOT/scripts/loop.sh" 2>/dev/null || true
  update_models_env

  log "Verifying..."
  verify_setup || warn "Verification failed — run: ./scripts/install.sh --repair"

  echo ""
  echo "=============================================="
  echo " Setup complete"
  echo "=============================================="
  echo "  Ollama:    $(ollama --version 2>/dev/null | head -1)"
  echo "  Models:    $(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
  echo "  OpenCode:  $(command -v opencode || echo 'not found')"
  echo ""
  echo "  source ~/.zshrc          # load OPENCODE_ENABLE_EXA"
  echo "  ./scripts/install.sh --verify"
  echo "  ./scripts/install.sh --upgrade"
  echo "  opencode                 # start terminal agent"
  echo "  Optional Zoo Code: docs/setup-zoocode.md"
  echo "=============================================="
}

version_line() { "$@" 2>&1 | head -1 | tr -d '\n' || echo "n/a"; }

cmd_check_upgrades() {
  command -v brew >/dev/null || die "Homebrew required"
  local env_file="$REPO_ROOT/config/models.env"
  echo "=== Upgrade check (no changes) ==="
  echo ""
  echo "--- Tools ---"
  echo "  Ollama:       $(version_line ollama --version)"
  echo "  OpenCode:     $(version_line opencode --version)"
  echo "  llama-server: $(version_line llama-server --version)"
  echo ""
  for pkg in ollama llama.cpp; do
    if brew list "$pkg" >/dev/null 2>&1; then
      if brew outdated "$pkg" 2>/dev/null | grep -q .; then
        echo "  outdated: $pkg"
      else
        echo "  up to date: $pkg"
      fi
    else
      echo "  not installed: $pkg"
    fi
  done
  if brew list anomalyco/tap/opencode >/dev/null 2>&1; then
    if brew outdated anomalyco/tap/opencode 2>/dev/null | grep -q .; then
      echo "  outdated: opencode"
    else
      echo "  up to date: opencode"
    fi
  fi
  echo ""
  echo "--- Qwen models (local) ---"
  if command -v ollama >/dev/null; then
    ollama list 2>/dev/null | tail -n +2 | while read -r name id size _rest; do
      printf "  %-28s %s  %s\n" "$name" "$id" "$size"
    done
    echo ""
    echo "  Pinned in config/models.env:"
    echo "    PRIMARY:      ${PRIMARY_MODEL}"
    echo "    FAST:         ${FAST_MODEL} ← ${FAST_MODEL_SOURCE}"
    if [[ -f "$env_file" ]]; then
      grep -E '^(PRIMARY_DIGEST|FAST_DIGEST|UPGRADED_AT)=' "$env_file" 2>/dev/null | sed 's/^/    /' || true
    fi
    echo ""
    echo "  Monitor new releases:"
    echo "    https://ollama.com/library/qwen3-coder/tags"
    echo "    https://ollama.com/freehuntx/qwen3-coder/tags"
  else
    echo "  Ollama not installed"
  fi
  echo ""
  echo "Commands:"
  echo "  ./scripts/install.sh --upgrade-models   # re-pull Qwen models only (~fast if current)"
  echo "  ./scripts/install.sh --upgrade            # tools + models + config"
  echo "  See docs/UPGRADING.md"
}

cmd_upgrade_models() {
  command -v ollama >/dev/null || die "Ollama not installed"
  local before_p before_f before_fs
  before_p="$(ollama list 2>/dev/null | awk -v m="$PRIMARY_MODEL" '$1==m {print $2}')"
  before_f="$(ollama list 2>/dev/null | awk -v m="$FAST_MODEL" '$1==m {print $2}')"
  before_fs="$(ollama list 2>/dev/null | awk -v m="$FAST_MODEL_SOURCE" '$1==m {print $2}')"

  brew services start ollama 2>/dev/null || true
  wait_for_ollama

  log "Re-pulling $PRIMARY_MODEL..."
  ollama pull "$PRIMARY_MODEL"
  if [[ "$SKIP_FAST" != "1" ]]; then
    log "Re-pulling $FAST_MODEL_SOURCE..."
    ollama pull "$FAST_MODEL_SOURCE"
    if [[ "$FAST_MODEL" != "$FAST_MODEL_SOURCE" ]]; then
      log "Refreshing alias $FAST_MODEL → $FAST_MODEL_SOURCE"
      ollama cp "$FAST_MODEL_SOURCE" "$FAST_MODEL"
    fi
  fi

  local after_p after_f after_fs
  after_p="$(ollama list 2>/dev/null | awk -v m="$PRIMARY_MODEL" '$1==m {print $2}')"
  after_f="$(ollama list 2>/dev/null | awk -v m="$FAST_MODEL" '$1==m {print $2}')"
  after_fs="$(ollama list 2>/dev/null | awk -v m="$FAST_MODEL_SOURCE" '$1==m {print $2}')"

  update_models_env
  verify_setup || warn "Verification failed — run: ./scripts/install.sh --repair"

  echo ""
  echo "=============================================="
  echo " Model upgrade complete"
  if [[ "$before_p" != "$after_p" ]]; then
    echo "  $PRIMARY_MODEL: $before_p → $after_p (updated)"
  else
    echo "  $PRIMARY_MODEL: unchanged ($after_p)"
  fi
  if [[ "$SKIP_FAST" != "1" ]]; then
    if [[ "$before_fs" != "$after_fs" ]]; then
      echo "  $FAST_MODEL_SOURCE: $before_fs → $after_fs (updated)"
    else
      echo "  $FAST_MODEL_SOURCE: unchanged ($after_fs)"
    fi
    if [[ "$before_f" != "$after_f" ]]; then
      echo "  $FAST_MODEL (alias): $before_f → $after_f"
    fi
  fi
  echo "  Pinned in config/models.env (UPGRADED_AT, digests)"
  echo "=============================================="
}

cmd_upgrade() {
  command -v brew >/dev/null || die "Homebrew required"

  local before_o before_c before_l
  before_o="$(version_line ollama --version)"
  before_c="$(version_line opencode --version)"
  before_l="$(version_line llama-server --version)"

  if [[ "$SKIP_BREW" != "1" ]]; then
    brew update
    for pkg in ollama llama.cpp; do
      if brew list "$pkg" >/dev/null 2>&1 && brew outdated "$pkg" 2>/dev/null | grep -q .; then
        log "Upgrading $pkg..."
        brew upgrade "$pkg"
      fi
    done
    brew tap anomalyco/tap 2>/dev/null || true
    if brew list anomalyco/tap/opencode >/dev/null 2>&1 && brew outdated anomalyco/tap/opencode 2>/dev/null | grep -q .; then
      log "Upgrading opencode..."
      brew upgrade anomalyco/tap/opencode
    fi
    if command -v opencode >/dev/null && ! brew list anomalyco/tap/opencode >/dev/null 2>&1; then
      opencode upgrade || warn "opencode upgrade failed"
    fi
  fi

  brew services start ollama 2>/dev/null || true
  wait_for_ollama
  ensure_ollama_post_install

  if [[ "$SKIP_MODELS" != "1" ]]; then
    ollama pull "$PRIMARY_MODEL"
    if [[ "$SKIP_FAST" != "1" ]]; then
      ollama pull "$FAST_MODEL_SOURCE"
      [[ "$FAST_MODEL" != "$FAST_MODEL_SOURCE" ]] && ollama cp "$FAST_MODEL_SOURCE" "$FAST_MODEL"
    fi
    [[ "$CREATE_64K" == "1" ]] && create_64k_variant
  fi

  local model_for_config="$PRIMARY_MODEL"
  [[ "$CREATE_64K" == "1" ]] && ollama list 2>/dev/null | grep -q "$CONTEXT_MODEL" && model_for_config="$CONTEXT_MODEL"

  export MODEL_FOR_CONFIG="$model_for_config"
  configure_opencode
  install_shell_env
  update_models_env
  verify_setup || warn "Verification failed — run: ./scripts/install.sh --repair"

  echo ""
  echo "=============================================="
  echo " Upgrade complete"
  echo "  Ollama:       $before_o → $(version_line ollama --version)"
  echo "  OpenCode:     $before_c → $(version_line opencode --version)"
  echo "  llama-server: $before_l → $(version_line llama-server --version)"
  echo "=============================================="
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "${1:-}" in
  --verify)  verify_setup ;;
  --repair)  cmd_repair ;;
  --upgrade)        cmd_upgrade ;;
  --upgrade-models) cmd_upgrade_models ;;
  --check)          cmd_check_upgrades ;;
  -h|--help)
    sed -n '2,18p' "$0"
    ;;
  "")        cmd_install ;;
  *)         die "Unknown option: $1 (try --help)" ;;
esac
