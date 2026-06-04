#!/usr/bin/env bash
# Automated setup for steps that need no GUI clicks.
# Run from repo root: ./scripts/install.sh
#
# Does NOT install VS Code extension (Step 8 — manual).
# Model download (Step 2) runs here but takes ~15–30 min for 30B.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIMARY_MODEL="${PRIMARY_MODEL:-qwen3-coder:30b}"
FAST_MODEL="${FAST_MODEL:-qwen3-coder:14b}"
PULL_FAST="${PULL_FAST:-0}"   # set PULL_FAST=1 to also pull 14B
CREATE_64K="${CREATE_64K:-1}" # set CREATE_64K=0 to skip Modelfile

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# --- Homebrew ---
if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew not found. Install from https://brew.sh then re-run this script."
fi

# --- Node (optional if nvm already present) ---
if ! command -v node >/dev/null 2>&1; then
  log "Installing Node.js..."
  brew install node
else
  log "Node already installed: $(node --version)"
fi

# --- Ollama ---
if ! command -v ollama >/dev/null 2>&1; then
  log "Installing Ollama..."
  brew install ollama
else
  log "Ollama already installed: $(ollama --version 2>/dev/null || true)"
fi

log "Starting Ollama service..."
brew services start ollama

log "Waiting for Ollama API..."
for i in {1..30}; do
  if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -sf http://127.0.0.1:11434/api/tags >/dev/null || die "Ollama API not responding on :11434"

# --- Homebrew Ollama 0.30+ needs llama-server for GGUF models ---
"$REPO_ROOT/scripts/fix-llama-server.sh"

# --- Pull models ---
log "Pulling primary model: $PRIMARY_MODEL (this may take a while)..."
ollama pull "$PRIMARY_MODEL"

if [[ "$PULL_FAST" == "1" ]]; then
  log "Pulling fast model: $FAST_MODEL..."
  ollama pull "$FAST_MODEL"
fi

# --- 64k context variant ---
MODEL_FOR_CONFIG="$PRIMARY_MODEL"
if [[ "$CREATE_64K" == "1" ]]; then
  log "Creating 64k context variant: qwen3-coder-64k..."
  cat > /tmp/Modelfile.local-agent <<EOF
FROM $PRIMARY_MODEL
PARAMETER num_ctx 65536
EOF
  ollama create qwen3-coder-64k -f /tmp/Modelfile.local-agent
  MODEL_FOR_CONFIG="qwen3-coder-64k"
fi

# --- OpenCode ---
if ! command -v opencode >/dev/null 2>&1; then
  log "Installing OpenCode..."
  if brew tap anomalyco/tap 2>/dev/null; then
    brew install anomalyco/tap/opencode || {
      log "brew install failed; trying curl installer..."
      curl -fsSL https://opencode.ai/install | bash
    }
  else
    curl -fsSL https://opencode.ai/install | bash
  fi
else
  log "OpenCode already installed: $(opencode --version 2>/dev/null || true)"
fi

# --- OpenCode config ---
log "Writing ~/.config/opencode/opencode.json..."
mkdir -p ~/.config/opencode
if [[ -f "$REPO_ROOT/config/opencode.json.example" ]]; then
  cp "$REPO_ROOT/config/opencode.json.example" ~/.config/opencode/opencode.json
  # Point default model at 64k variant if created
  if [[ "$MODEL_FOR_CONFIG" == "qwen3-coder-64k" ]]; then
    sed -i '' 's/"model": "ollama\/qwen3-coder:30b"/"model": "ollama\/qwen3-coder-64k"/' ~/.config/opencode/opencode.json 2>/dev/null || \
    sed -i 's/"model": "ollama\/qwen3-coder:30b"/"model": "ollama\/qwen3-coder-64k"/' ~/.config/opencode/opencode.json
  fi
fi

# --- Repo config pin ---
if [[ ! -f "$REPO_ROOT/config/models.env" ]]; then
  cp "$REPO_ROOT/config/models.env.example" "$REPO_ROOT/config/models.env"
  log "Created config/models.env (edit PRIMARY_MODEL if needed)"
fi

chmod +x "$REPO_ROOT/scripts/loop.sh" 2>/dev/null || true
chmod +x "$REPO_ROOT/scripts/fix-llama-server.sh" "$REPO_ROOT/scripts/verify.sh" 2>/dev/null || true

log "Running fast verification (no model load)..."
if ! "$REPO_ROOT/scripts/verify.sh"; then
  echo "WARNING: verification failed — try: ./scripts/fix-llama-server.sh && ./scripts/verify.sh" >&2
fi

log "Optional: run 'ollama launch opencode' for guided first launch"

echo ""
echo "=============================================="
echo " Automated setup complete (Steps 0–7)"
echo "=============================================="
echo ""
echo "  Ollama:    $(ollama --version 2>/dev/null | head -1)"
echo "  Models:    $(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
echo "  OpenCode:  $(command -v opencode || echo 'not found')"
echo "  Config:    ~/.config/opencode/opencode.json"
echo ""
echo " Verify setup (fast, ~10s):"
echo "   ./scripts/verify.sh"
echo ""
echo " Verify full inference (slow, ~2 min first load):"
echo "   VERIFY_INFERENCE=1 ./scripts/verify.sh"
echo ""
echo " Verify /loop:"
echo "   cd $REPO_ROOT && ./scripts/loop.sh \"create LOOP_TEST.txt and output LOOP_COMPLETE\""
echo ""
echo " LAST STEP (manual): VS Code + Zoo Code — see docs/SETUP.md Step 8"
echo "=============================================="
