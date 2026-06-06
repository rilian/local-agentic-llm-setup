# Models — Native MLX on Apple Silicon

This stack runs models **directly on Apple MLX** via [`mlx-lm`](https://github.com/ml-explore/mlx-lm).

---

## Default model

| Setting | Value |
|---------|-------|
| **HuggingFace ID** | `mlx-community/Qwen3.5-9B-OptiQ-4bit` |
| **OpenCode ID** | `mlx/mlx-community/Qwen3.5-9B-OptiQ-4bit` |
| **Quantization** | OptiQ 4-bit (mixed 4/8-bit) |
| **Disk** | ~7 GB |
| **RAM when loaded** | ~9 GB |
| **Context** | 32k (OpenCode config) |
| **Updated** | 2026-05-31 |

```bash
opencode    # default model
```

---

## Why Qwen3.5 9B OptiQ?

- **Qwen3.5** — current generation (newer than Qwen3)
- **OptiQ** — sensitivity-aware mixed-precision quant tuned for agent/tool/code use
- Native **MLX** weights from [mlx-community](https://huggingface.co/mlx-community)
- Fits **24 GB** M4 Pro with room for OpenCode and dev tools

---

## Server settings

Configured in `scripts/mlx-serve.sh` and launchd:

| Setting | Default | Purpose |
|---------|---------|---------|
| `MLX_PORT` | `8080` | OpenAI-compatible API port |
| `MLX_MAX_TOKENS` | `8192` | Max generation per request |
| `MLX_CHAT_TEMPLATE_ARGS` | `{"enable_thinking":false}` | Disable thinking mode for agent use |

---

## Alternatives (24 GB Mac)

| Model | RAM | Notes |
|-------|-----|-------|
| `mlx-community/Qwen3-8B-4bit` | ~5 GB | Lighter Qwen3 |
| `mlx-community/Qwen3.5-9B-OptiQ-4bit` | ~9 GB | **Default** |
| `mlx-community/Qwen3-14B-4bit` | ~9 GB | Larger Qwen3 dense |

Switch model:

```bash
PRIMARY_MODEL=mlx-community/Qwen3-14B-4bit ./scripts/install.sh --repair
```

---

## Speed tips

1. **Keep server running** — launchd loads model once; `./scripts/mlx-serve.sh status`
2. **Fresh OpenCode session** for long tasks — less history = faster prefill
3. **Disable unused MCPs** — each MCP adds latency
4. **Pre-warm** (optional): `curl http://127.0.0.1:8080/v1/models` after reboot

---

## Model cache location

Weights live in `~/.cache/huggingface/hub/`. Remove unused models:

```bash
./scripts/install.sh --cleanup
```

---

## Monitoring updates

https://huggingface.co/mlx-community/Qwen3.5-9B-OptiQ-4bit

Re-download:

```bash
./scripts/install.sh --upgrade-models
```
