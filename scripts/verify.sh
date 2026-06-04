#!/usr/bin/env bash
# Fast setup verification — finishes in seconds (no 30B model load).
# Optional full inference test: VERIFY_INFERENCE=1 ./scripts/verify.sh
# Auto-fix llama-server: FIX_LLAMA_SERVER=1 ./scripts/verify.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIMARY_MODEL="${PRIMARY_MODEL:-qwen3-coder-64k}"
VERIFY_INFERENCE="${VERIFY_INFERENCE:-0}"
FIX_LLAMA_SERVER="${FIX_LLAMA_SERVER:-0}"
FAIL=0

ok()   { echo "OK   $*"; }
fail() { echo "FAIL $*" >&2; FAIL=1; }

# --- Ollama API ---
if curl -sf --max-time 5 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  ok "Ollama API responding on :11434"
else
  fail "Ollama API not responding — run: brew services start ollama"
fi

# --- llama-server binary (Homebrew Ollama 0.30+ gap) ---
if command -v ollama >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  BREW_PREFIX="$(brew --prefix)"
  OLLAMA_VER="$(ollama --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  TARGET="${BREW_PREFIX}/Cellar/ollama/${OLLAMA_VER}/libexec/lib/ollama/llama-server"
  if [[ -x "$TARGET" ]] || { [[ -L "$TARGET" ]] && command -v llama-server >/dev/null && [[ -x "$(command -v llama-server)" ]]; }; then
    ok "llama-server present at $TARGET"
  else
    fail "llama-server missing at $TARGET"
    if [[ "$FIX_LLAMA_SERVER" == "1" ]]; then
      "$REPO_ROOT/scripts/fix-llama-server.sh"
    else
      echo "      Fix: ./scripts/fix-llama-server.sh" >&2
    fi
  fi
else
  fail "ollama or brew not in PATH"
fi

# --- Models listed ---
MODELS="$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
if [[ -n "$MODELS" ]]; then
  ok "Models: $MODELS"
else
  fail "No models installed — run: ./scripts/install.sh"
fi

# --- Fast llama-server runtime probe (~1s if broken, may timeout if OK and loading) ---
if curl -sf --max-time 5 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  PROBE="$(curl -s --max-time 10 http://127.0.0.1:11434/api/generate \
    -d "{\"model\":\"${PRIMARY_MODEL}\",\"prompt\":\"x\",\"stream\":false}" 2>&1 || true)"
  if echo "$PROBE" | grep -q 'llama-server binary not found'; then
    fail "Ollama cannot start llama-server (runtime probe)"
    echo "      Fix: ./scripts/fix-llama-server.sh  (then re-run this script)" >&2
  elif echo "$PROBE" | grep -q '"response"'; then
    ok "Ollama inference probe succeeded (model already loaded)"
  else
    ok "Ollama inference probe: no llama-server error (model load may take ~2 min on first use)"
  fi
fi

# --- OpenCode ---
if command -v opencode >/dev/null 2>&1; then
  ok "OpenCode $(opencode --version 2>/dev/null | head -1)"
else
  fail "OpenCode not installed — run: ./scripts/install.sh"
fi

# --- Optional slow inference (loads 30B into RAM) ---
if [[ "$VERIFY_INFERENCE" == "1" ]] && [[ "$FAIL" -eq 0 ]]; then
  echo "==> Full inference test (first run ~2 min)..."
  OUT="$(curl -sf --max-time 180 http://127.0.0.1:11434/api/generate \
    -d "{\"model\":\"${PRIMARY_MODEL}\",\"prompt\":\"Reply with exactly: setup ok\",\"stream\":false}" \
    | grep -o 'setup ok' || true)"
  if [[ "$OUT" == "setup ok" ]]; then
    ok "Full inference returned 'setup ok'"
  else
    fail "Full inference did not return 'setup ok' within 180s"
  fi
fi

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All checks passed."
  if [[ "$VERIFY_INFERENCE" != "1" ]]; then
    echo "Optional: VERIFY_INFERENCE=1 ./scripts/verify.sh  (slow — loads 30B model)"
  fi
  exit 0
fi

echo "Some checks failed." >&2
exit 1
