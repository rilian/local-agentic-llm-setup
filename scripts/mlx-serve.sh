#!/usr/bin/env bash
# Manage the local MLX inference server (mlx-lm OpenAI-compatible API).
#
# Usage:
#   ./scripts/mlx-serve.sh start|stop|restart|status|logs
#
# Env (or config/models.env):
#   PRIMARY_MODEL=mlx-community/Qwen3.5-9B-OptiQ-4bit
#   MLX_HOST=127.0.0.1
#   MLX_PORT=8080
#   MLX_MAX_TOKENS=8192
#   MLX_CHAT_TEMPLATE_ARGS='{"enable_thinking":false}'

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="${REPO_ROOT}/.venv"
PYTHON="${VENV}/bin/python"
PLIST="${HOME}/Library/LaunchAgents/ai.local.mlx-server.plist"
LOG_OUT="/tmp/mlx-server.log"
LOG_ERR="/tmp/mlx-server.err"

_CLI_MODEL="${PRIMARY_MODEL:-}"
MLX_HOST="${MLX_HOST:-127.0.0.1}"
MLX_PORT="${MLX_PORT:-8080}"
MLX_MAX_TOKENS="${MLX_MAX_TOKENS:-8192}"
MLX_CHAT_TEMPLATE_ARGS='{"enable_thinking":false}'

if [[ -f "$REPO_ROOT/config/models.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/config/models.env"
fi
PRIMARY_MODEL="${_CLI_MODEL:-${PRIMARY_MODEL:-mlx-community/Qwen3.5-9B-OptiQ-4bit}}"
if [[ "$PRIMARY_MODEL" != */* ]]; then
  PRIMARY_MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
fi
if [[ "$MLX_CHAT_TEMPLATE_ARGS" != *'"'* ]]; then
  MLX_CHAT_TEMPLATE_ARGS='{"enable_thinking":false}'
fi

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

ensure_venv() {
  [[ -x "$PYTHON" ]] || die "Python venv missing — run: ./scripts/install.sh"
}

write_plist() {
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>ai.local.mlx-server</string>
  <key>ProgramArguments</key>
  <array>
    <string>${PYTHON}</string>
    <string>-m</string>
    <string>mlx_lm</string>
    <string>server</string>
    <string>--model</string>
    <string>${PRIMARY_MODEL}</string>
    <string>--host</string>
    <string>${MLX_HOST}</string>
    <string>--port</string>
    <string>${MLX_PORT}</string>
    <string>--max-tokens</string>
    <string>${MLX_MAX_TOKENS}</string>
    <string>--chat-template-args</string>
    <string>${MLX_CHAT_TEMPLATE_ARGS}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${REPO_ROOT}</string>
  <key>StandardOutPath</key>
  <string>${LOG_OUT}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_ERR}</string>
</dict>
</plist>
EOF
}

wait_for_api() {
  local i
  for i in {1..120}; do
    if curl -sf --max-time 2 "http://${MLX_HOST}:${MLX_PORT}/v1/models" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

cmd_start() {
  ensure_venv
  write_plist
  launchctl bootout "gui/$(id -u)/ai.local.mlx-server" 2>/dev/null || \
    launchctl unload "$PLIST" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || \
    launchctl load "$PLIST"
  log "MLX server starting on http://${MLX_HOST}:${MLX_PORT} (model: ${PRIMARY_MODEL})"
  if wait_for_api; then
    log "MLX API ready"
  else
    warn "API not ready yet — model may still be downloading. Check: $0 logs"
  fi
}

cmd_stop() {
  launchctl bootout "gui/$(id -u)/ai.local.mlx-server" 2>/dev/null || \
    launchctl unload "$PLIST" 2>/dev/null || true
  log "MLX server stopped"
}

cmd_restart() {
  cmd_stop
  sleep 1
  cmd_start
}

cmd_status() {
  if curl -sf --max-time 3 "http://${MLX_HOST}:${MLX_PORT}/v1/models" >/dev/null 2>&1; then
    echo "MLX API:  up  http://${MLX_HOST}:${MLX_PORT}/v1"
    curl -sf "http://${MLX_HOST}:${MLX_PORT}/v1/models" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for m in d.get('data', []):
    print('  model:', m.get('id', '?'))
" 2>/dev/null || true
  else
    echo "MLX API:  down  http://${MLX_HOST}:${MLX_PORT}/v1"
    echo "  Start: ./scripts/mlx-serve.sh start"
  fi
  if launchctl print "gui/$(id -u)/ai.local.mlx-server" >/dev/null 2>&1; then
    echo "LaunchAgent: loaded (ai.local.mlx-server)"
  else
    echo "LaunchAgent: not loaded"
  fi
}

cmd_logs() {
  echo "=== stdout (${LOG_OUT}) ==="
  tail -n 40 "$LOG_OUT" 2>/dev/null || echo "(empty)"
  echo ""
  echo "=== stderr (${LOG_ERR}) ==="
  tail -n 40 "$LOG_ERR" 2>/dev/null || echo "(empty)"
}

case "${1:-status}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_restart ;;
  status)  cmd_status ;;
  logs)    cmd_logs ;;
  -h|--help)
    sed -n '2,12p' "$0"
    ;;
  *) die "Unknown command: $1 (try start|stop|restart|status|logs)" ;;
esac
