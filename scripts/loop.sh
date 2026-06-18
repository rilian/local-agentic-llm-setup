#!/usr/bin/env bash
# Long-running agent loop — terminal equivalent of /loop
# Approval-only: each file edit and shell command requires your OK in the OpenCode UI.
# Usage: ./scripts/loop.sh [--max N] [--model provider/model] "your task"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/colors.sh"

MAX_ITERATIONS=25
MODEL=""
TASK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--max N] [--model mlx/mlx-community/Qwen3.5-4B-OptiQ-4bit] \"task description\""
      exit 0
      ;;
    *)
      TASK="$1"
      shift
      ;;
  esac
done

if [[ -z "$TASK" ]]; then
  error_msg "provide a task description."
  dim_line "Example: $0 \"Add tests and fix lint — LOOP_COMPLETE when done\""
  exit 1
fi

if ! command -v opencode >/dev/null 2>&1; then
  die "opencode not found. Install: curl -fsSL https://opencode.ai/install | bash"
fi

PROMPT_FILE="$REPO_ROOT/prompts/loop.md"
LOOP_PROMPT=$(sed "s/{{TASK}}/$TASK/" "$PROMPT_FILE")

MODEL_ARGS=()
if [[ -n "$MODEL" ]]; then
  MODEL_ARGS=(--model "$MODEL")
fi

banner "Loop start (max $MAX_ITERATIONS iterations)"
label_value "Task" "$TASK"
echo ""
dim_line "Approval-only: approve each action in the OpenCode prompt (never use --dangerously-skip-permissions)."
echo ""

for ((i=1; i<=MAX_ITERATIONS; i++)); do
  section "Iteration $i / $MAX_ITERATIONS"

  if [[ $i -eq 1 ]]; then
    PROMPT="$LOOP_PROMPT"
    CONTINUE_ARGS=()
  else
    PROMPT="Continue the loop task. Previous iteration did not output LOOP_COMPLETE. Keep working: $TASK"
    CONTINUE_ARGS=(--continue)
  fi

  OUTPUT=$(mktemp)
  set +e
  opencode run -i "${MODEL_ARGS[@]}" "${CONTINUE_ARGS[@]}" "$PROMPT" 2>&1 | tee "$OUTPUT"
  EXIT_CODE=${PIPESTATUS[0]}
  set -e

  if grep -q 'LOOP_COMPLETE' "$OUTPUT"; then
    echo ""
    success_msg "Loop finished (LOOP_COMPLETE) after $i iteration(s)"
    rm -f "$OUTPUT"
    exit 0
  fi

  if grep -q 'LOOP_BLOCKED' "$OUTPUT"; then
    echo ""
    warn "Loop blocked by agent"
    rm -f "$OUTPUT"
    exit 2
  fi

  rm -f "$OUTPUT"

  if [[ $EXIT_CODE -ne 0 ]]; then
    warn "opencode exited with code $EXIT_CODE"
  fi

  sleep 2
done

echo ""
error_msg "Loop stopped: max iterations ($MAX_ITERATIONS) reached without LOOP_COMPLETE"
exit 1
