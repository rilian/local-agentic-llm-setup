#!/usr/bin/env bash
# Homebrew Ollama 0.30+ does not ship llama-server — GGUF models fail without this.
# Run: ./scripts/fix-llama-server.sh
# Safe to re-run after `brew upgrade ollama`.

set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew required." >&2
  exit 1
fi
if ! command -v ollama >/dev/null 2>&1; then
  echo "ERROR: ollama not installed." >&2
  exit 1
fi

BREW_PREFIX="$(brew --prefix)"
OLLAMA_VER="$(ollama --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
TARGET="${BREW_PREFIX}/Cellar/ollama/${OLLAMA_VER}/libexec/lib/ollama/llama-server"

llama_server_resolves() {
  if [[ -x "$TARGET" ]]; then
    return 0
  fi
  if [[ -L "$TARGET" ]] && command -v llama-server >/dev/null 2>&1 && [[ -x "$(command -v llama-server)" ]]; then
    return 0
  fi
  return 1
}

if ! command -v llama-server >/dev/null 2>&1 || ! llama_server_resolves; then
  echo "==> Installing llama.cpp (provides llama-server)..."
  brew install llama.cpp
  mkdir -p "$(dirname "$TARGET")"
  ln -sf "$(command -v llama-server)" "$TARGET"
  echo "==> Linked llama-server → $TARGET"
else
  echo "==> llama-server already linked at $TARGET"
fi

echo "==> Restarting Ollama (required — running daemon won't see new binary until restart)..."
brew services restart ollama

echo "==> Waiting for Ollama API..."
for _ in {1..30}; do
  if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -sf http://127.0.0.1:11434/api/tags >/dev/null || {
  echo "ERROR: Ollama API not responding on :11434" >&2
  exit 1
}

if llama_server_resolves; then
  echo "OK: llama-server ready at $TARGET"
else
  echo "ERROR: llama-server still not usable at $TARGET" >&2
  exit 1
fi
