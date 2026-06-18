#!/usr/bin/env bash
# Manage the local MLX inference server (Rapid-MLX OpenAI-compatible API).
#
# Usage:
#   ./scripts/mlx-serve.sh start|stop|restart|status|logs
#
# Optional: PRIMARY_MODEL=mlx-community/... (or set in config/models.env)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/colors.sh"
VENV="${REPO_ROOT}/.venv"
PYTHON="${VENV}/bin/python"
RAPID_MLX="${VENV}/bin/rapid-mlx"
PLIST="${HOME}/Library/LaunchAgents/ai.local.mlx-server.plist"
LOG_OUT="/tmp/mlx-server.log"
LOG_ERR="/tmp/mlx-server.err"

_CLI_MODEL="${PRIMARY_MODEL:-}"
DEFAULT_MODEL="mlx-community/Qwen3-8B-4bit"
MLX_HOST="127.0.0.1"
MLX_PORT="8080"
MLX_MAX_TOKENS="8192"

if [[ -f "$REPO_ROOT/config/models.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/config/models.env"
fi
PRIMARY_MODEL="${_CLI_MODEL:-${PRIMARY_MODEL:-$DEFAULT_MODEL}}"
if [[ "$PRIMARY_MODEL" != */* ]]; then
  PRIMARY_MODEL="$DEFAULT_MODEL"
fi

# log, warn, die — scripts/colors.sh

ensure_venv() {
  [[ -x "$PYTHON" ]] || die "Python venv missing — run: ./scripts/install.sh"
  [[ -x "$RAPID_MLX" ]] || die "rapid-mlx not installed — run: ./scripts/install.sh"
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
    <string>${RAPID_MLX}</string>
    <string>serve</string>
    <string>${PRIMARY_MODEL}</string>
    <string>--host</string>
    <string>${MLX_HOST}</string>
    <string>--port</string>
    <string>${MLX_PORT}</string>
    <string>--max-tokens</string>
    <string>${MLX_MAX_TOKENS}</string>
    <string>--no-thinking</string>
    <string>--enable-auto-tool-choice</string>
    <string>--tool-call-parser</string>
    <string>auto</string>
    <string>--enable-prefix-cache</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>RAPID_MLX_TELEMETRY</key>
    <string>0</string>
  </dict>
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
    printf '%b\n' "${C_GREEN}${C_BOLD}MLX API:${C_RESET}  ${C_GREEN}up${C_RESET}  http://${MLX_HOST}:${MLX_PORT}/v1"
    curl -sf "http://${MLX_HOST}:${MLX_PORT}/v1/models" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for m in d.get('data', []):
    print('  model:', m.get('id', '?'))
" 2>/dev/null || true
  else
    printf '%b\n' "${C_RED}${C_BOLD}MLX API:${C_RESET}  ${C_RED}down${C_RESET}  http://${MLX_HOST}:${MLX_PORT}/v1"
    dim_line "  Start: ./scripts/mlx-serve.sh start"
  fi
  if launchctl print "gui/$(id -u)/ai.local.mlx-server" >/dev/null 2>&1; then
    printf '%b\n' "${C_GREEN}LaunchAgent:${C_RESET} loaded (ai.local.mlx-server)"
  else
    printf '%b\n' "${C_YELLOW}LaunchAgent:${C_RESET} not loaded"
  fi
}

cmd_logs() {
  section "stdout (${LOG_OUT})"
  tail -n 40 "$LOG_OUT" 2>/dev/null || dim_line "(empty)"
  echo ""
  section "stderr (${LOG_ERR})"
  tail -n 40 "$LOG_ERR" 2>/dev/null || dim_line "(empty)"
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
