# Benchmarks — Qwen3.5 9B OptiQ MLX

Run benchmarks on your machine:

```bash
./scripts/install.sh --benchmark
```

Results are written to `results/benchmark-YYYYMMDD-HHMMSS.md` and `.json`.

---

## What is measured

Five prompts (general + coding) against the MLX OpenAI-compatible API:

| Category | Prompt |
|----------|--------|
| general | 3-word greeting |
| general | capital of France |
| general | hash map explanation |
| coding | fix ZeroDivisionError bug |
| coding | write palindrome function |

Each run records cold (first) and warm timings.

---

## Expected performance (M4 Pro 24 GB)

Exact numbers vary by mlx-lm version and system load. After `./scripts/install.sh --benchmark`, paste results here.

| Metric | Typical range |
|--------|---------------|
| Cold first prompt | 30–120 s (model load + inference) |
| Warm prompts | 3–15 s each |
| Throughput | 30–80 tok/s (warm) |

---

## Recommendations

1. **Keep MLX server running** via launchd — avoids reload penalty
2. **Disable thinking** — already set via `enable_thinking: false`
3. **Use `./scripts/loop.sh`** for multi-step tasks instead of one giant prompt
4. **Compare runs** in `results/` after mlx-lm upgrades

---

## OpenCode vs raw API

OpenCode adds overhead (MCP, tool routing, history). Raw API benchmarks in this repo measure **model speed only**. Expect OpenCode turns to take longer than benchmark numbers.
