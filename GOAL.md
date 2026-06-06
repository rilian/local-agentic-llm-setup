# Goal: Local Agentic LLM (Mac M4 Pro)

## Summary

**Terminal-first** local coding agent using **native MLX** (Apple `mlx-lm` server) + **OpenCode** + `./scripts/loop.sh`. **ChatGPT** for general GUI chat.

Models run directly on Apple MLX via an OpenAI-compatible local API.

---

## Setup automation summary

**Single entry point:** `./scripts/install.sh`

| Step | What | Automatic? | How |
|------|------|------------|-----|
| 0 | Homebrew | Manual once | [brew.sh](https://brew.sh) if missing |
| 1 | Python venv + mlx-lm | **Yes** | `install.sh` → `.venv` |
| 2 | Download Qwen3.5 9B MLX | **Yes** (slow) | ~7 GB from HuggingFace |
| 3 | MLX server (launchd) | **Yes** | `scripts/mlx-serve.sh` |
| 4 | OpenCode CLI | **Yes** | `install.sh` |
| 5 | OpenCode → MLX config | **Yes** | `install.sh` |
| 5b | Web search shell env | **Yes** | `OPENCODE_ENABLE_EXA=1` |
| 6 | Terminal daily use | **You run** | `opencode` |
| 7 | `/loop` long tasks | **You run** | `./scripts/loop.sh "task"` |
| 8 | Pin model version | **Yes** | `config/models.env` |

```bash
cd /path/to/local-agentic-llm-setup
chmod +x scripts/install.sh scripts/loop.sh scripts/mlx-serve.sh
./scripts/install.sh
```

| Command | Purpose |
|---------|---------|
| `./scripts/install.sh --verify` | Verify (~15s) |
| `./scripts/install.sh --repair` | Re-apply MLX server + OpenCode config |
| `./scripts/install.sh --upgrade` | Upgrade mlx-lm + OpenCode |
| `./scripts/mlx-serve.sh status` | Check MLX API |
| `./scripts/install.sh --benchmark` | Speed/quality benchmarks |

---

## Constraints

- Terminal agent: OpenCode + `scripts/loop.sh`
- **Native MLX** inference via `mlx-lm`
- Privacy-first, local models
- **Approval-only:** never use `--dangerously-skip-permissions`
- GUI chat: ChatGPT (general)

---

## Hardware

MacBook Pro M4 Pro, 24 GB RAM.

**Primary model:** `mlx-community/Qwen3.5-9B-OptiQ-4bit` at **32k context** via `http://127.0.0.1:8080/v1`

Full guide: **[docs/SETUP.md](docs/SETUP.md)**

---

## Success criteria

- [ ] `./scripts/install.sh` completes without errors
- [ ] `./scripts/install.sh --verify` passes
- [ ] `./scripts/mlx-serve.sh status` → API up, model loaded
- [ ] OpenCode tool test: reads a file via tool, not prose
