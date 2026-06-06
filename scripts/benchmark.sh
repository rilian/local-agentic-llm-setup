#!/usr/bin/env bash
# Benchmark Qwen3.5 9B OptiQ MLX via mlx-lm OpenAI-compatible API.
#
# Usage:
#   ./scripts/benchmark.sh
#   ./scripts/benchmark.sh --json
#
# Results: results/benchmark-YYYYMMDD-HHMMSS.md (+ .json)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIMARY_MODEL="${PRIMARY_MODEL:-mlx-community/Qwen3.5-9B-OptiQ-4bit}"
MLX_API_BASE="${MLX_API_BASE:-http://127.0.0.1:8080}"
JSON_ONLY=0

if [[ -f "$REPO_ROOT/config/models.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/config/models.env"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *) shift ;;
  esac
done

RESULTS_DIR="$REPO_ROOT/results"
mkdir -p "$RESULTS_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_MD="$RESULTS_DIR/benchmark-${STAMP}.md"
OUT_JSON="$RESULTS_DIR/benchmark-${STAMP}.json"

run_prompt() {
  local category="$1" label="$2" prompt="$3" max_tokens="${4:-512}"
  local tmp body
  tmp="$(mktemp)"
  body="$(python3 - "$PRIMARY_MODEL" "$prompt" "$max_tokens" <<'PY'
import json, sys
model, prompt, max_tok = sys.argv[1:4]
print(json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": int(max_tok),
    "stream": False,
}))
PY
)"
  local start end elapsed
  start=$(python3 -c "import time; print(int(time.time()*1000))")
  curl -sf --max-time 300 "${MLX_API_BASE}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "$body" > "$tmp" 2>/dev/null || echo '{"error":"timeout"}' > "$tmp"
  end=$(python3 -c "import time; print(int(time.time()*1000))")
  elapsed=$(( end - start ))
  python3 - "$tmp" "$PRIMARY_MODEL" "$category" "$label" "$elapsed" <<'PY'
import json, sys
path, model, category, label, elapsed = sys.argv[1:6]
with open(path) as f:
    d = json.load(f)
err = d.get("error")
choices = d.get("choices") or [{}]
content = (choices[0].get("message") or {}).get("content") or ""
usage = d.get("usage") or {}
completion = usage.get("completion_tokens") or 0
prompt_t = usage.get("prompt_tokens") or 0
rate = round(completion * 1000 / int(elapsed), 1) if int(elapsed) > 0 and completion else 0
print(json.dumps({
    "model": model,
    "category": category,
    "label": label,
    "error": err,
    "content_len": len(content.strip()),
    "content_preview": content.strip()[:200].replace("\n", " "),
    "total_ms": int(elapsed),
    "prompt_tokens": prompt_t,
    "completion_tokens": completion,
    "eval_rate": rate,
}))
PY
  rm -f "$tmp"
}

PROMPTS=(
  'general|hi|Say hi in exactly 3 words.|512'
  'general|capitals|What is the capital of France? One word only.|256'
  'general|explain|Explain what a hash map is in 2 sentences.|1024'
  'coding|fix-bug|Fix this Python bug and return only the corrected function:\ndef avg(nums):\n    return sum(nums) / len(nums)\n# avg([]) raises ZeroDivisionError|1024'
  'coding|write-fn|Write a Python function is_palindrome(s: str) -> bool. Return only the function, no explanation.|1024'
)

for _ in {1..30}; do
  curl -sf --max-time 5 "${MLX_API_BASE}/v1/models" >/dev/null && break
  sleep 2
done
curl -sf --max-time 5 "${MLX_API_BASE}/v1/models" >/dev/null || { echo "MLX server not running — ./scripts/mlx-serve.sh start" >&2; exit 1; }

RESULTS=()
first=1
for entry in "${PROMPTS[@]}"; do
  IFS='|' read -r category label prompt max_tok <<< "$entry"
  phase="warm"
  [[ "$first" -eq 1 ]] && phase="cold"
  row="$(run_prompt "$category" "$label" "$prompt" "$max_tok")"
  row="$(echo "$row" | python3 -c "import json,sys; d=json.load(sys.stdin); d['phase']='$phase'; print(json.dumps(d))")"
  RESULTS+=("$row")
  first=0
done

python3 - "$OUT_JSON" "$OUT_MD" "$JSON_ONLY" "$REPO_ROOT" "${RESULTS[@]}" <<'PY'
import json, sys, platform, subprocess
from datetime import datetime, timezone
from pathlib import Path

out_json, out_md, json_only, repo_root = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
rows = [json.loads(r) for r in sys.argv[5:]]

def mlx_ver():
    py = Path(repo_root) / ".venv" / "bin" / "python"
    if py.exists():
        try:
            return subprocess.check_output(
                [str(py), "-c", "import mlx_lm; print(mlx_lm.__version__)"],
                text=True,
            ).strip()
        except Exception:
            pass
    return "unknown"

meta = {
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "mlx_lm": mlx_ver(),
    "platform": platform.platform(),
    "results": rows,
}
with open(out_json, "w") as f:
    json.dump(meta, f, indent=2)

if json_only:
    print(json.dumps(meta, indent=2))
    sys.exit(0)

lines = [
    "# Qwen3.5 9B OptiQ MLX benchmark",
    "",
    f"- **Run:** {meta['timestamp']}",
    f"- **Host:** {meta['platform']}",
    "",
    "## Summary",
    "",
    "| Phase | Category | Prompt | Total ms | tok/s | Content |",
    "|-------|----------|--------|----------|-------|---------|",
]
for r in rows:
    ok = "✓" if r["content_len"] > 0 and not r.get("error") else "✗"
    lines.append(
        f"| {r['phase']} | {r['category']} | {r['label']} | {r['total_ms']} | "
        f"{r['eval_rate']} | {ok} ({r['content_len']} chars) |"
    )

warm = [r for r in rows if r["phase"] == "warm"]
if warm:
    avg = sum(x["total_ms"] for x in warm) // len(warm)
    ok = sum(1 for x in warm if x["content_len"] > 0)
    lines += ["", f"**Warm average:** {avg} ms/prompt · {ok}/{len(warm)} OK", ""]

with open(out_md, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"Wrote {out_md}")
print(f"Wrote {out_json}")
PY
