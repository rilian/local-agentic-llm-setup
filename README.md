# Local Agentic LLM (Mac M4 Pro 24 GB)

Terminal-first **local coding agent** on Apple Silicon: **OpenCode** + **Rapid-MLX** inference server + `./scripts/loop.sh`.

- **Privacy-first** — models run locally via `http://127.0.0.1:8080/v1`
- **Approval-only** — never use `--dangerously-skip-permissions`
- **Hardware:** M4 Pro, 24 GB RAM (tuned for this machine)

**Default model:** [`mlx-community/Qwen3-8B-4bit`](https://huggingface.co/mlx-community/Qwen3-8B-4bit) (~5 GB disk, ~5 GB RAM, 32k context)

---

## Architecture

```
Terminal
├── opencode              # interactive agent (approve each action)
└── ./scripts/loop.sh     # long tasks with LOOP_COMPLETE
         │
         ▼
Rapid-MLX server :8080/v1  ←  Qwen3 8B 4-bit (Apple MLX, launchd)
```

Run OpenCode from your project directory: `cd myproject && opencode`.

---

## Quick start

**Prerequisite:** [Homebrew](https://brew.sh) (`brew --version`).

```bash
git clone <this-repo> ~/local-agentic-llm-setup
cd ~/local-agentic-llm-setup
chmod +x scripts/install.sh scripts/loop.sh scripts/mlx-serve.sh
./scripts/install.sh
```

First run downloads ~7 GB and may take 10–20 minutes. First inference loads weights into RAM (~30–90s).

---

## Commands

| Command | Purpose |
|---------|---------|
| `./scripts/install.sh` | Full install — includes verify + HF cache cleanup |
| `./scripts/install.sh --upgrade` | Full upgrade + repair (deps, OpenCode, model, verify, cleanup) |
| `./scripts/install.sh --upgrade --best-model` | Upgrade and switch to best model for 24 GB if catalog recommends |
| `./scripts/mlx-serve.sh status` | Check MLX API |
| `./scripts/mlx-serve.sh restart` | Restart MLX server |
| `opencode` | Start terminal agent |
| `./scripts/loop.sh "task"` | Long-running agent loop |

**Override model:** `PRIMARY_MODEL=mlx-community/Qwen3-14B-4bit ./scripts/install.sh --upgrade`

---

## What install does

1. Python venv (`.venv`) with `rapid-mlx`, `mlx`, `mlx-lm` (utilities), `huggingface_hub`
2. Downloads the default MLX model from HuggingFace
3. LaunchAgent `ai.local.mlx-server` on port **8080**
4. OpenCode CLI + `~/.config/opencode/opencode.json` (MLX provider)
5. `OPENCODE_ENABLE_EXA=1` in `~/.zshrc` (web search)
6. `config/models.env` — pinned model + versions
7. Removes unused HuggingFace model caches (keeps current model)
8. **Verify** — stack checks + agent tool test (model reads `README.md` via tool call)

---

## Daily use

```bash
source ~/.zshrc                    # once per session (EXA env)
./scripts/mlx-serve.sh status      # API should be "up"
opencode                           # approve edits and shell commands
```

Long task:

```bash
./scripts/loop.sh "Refactor auth — LOOP_COMPLETE when tests pass"
```

Switch model in session: `/models` in the OpenCode TUI.

---

## Model

| | |
|---|---|
| **HuggingFace** | `mlx-community/Qwen3-8B-4bit` |
| **OpenCode** | `mlx/mlx-community/Qwen3-8B-4bit` |
| **Quant** | uniform 4-bit |

**Why this model:** Best tool-calling reliability (F1=0.919), fast, fits comfortably in 24 GB.

**Alternatives (24 GB Mac):**

| Model | RAM | Notes |
|-------|-----|-------|
| `mlx-community/Qwen3-8B-4bit` | ~5 GB | **Default** — best tool-calling |
| `mlx-community/Qwen3.5-9B-OptiQ-4bit` | ~9 GB | Avoid — unreliable tool calls |
| `mlx-community/Qwen3-14B-4bit` | ~9 GB | Avoid — hallucinates instead of calling tools |

Server defaults (edit `scripts/mlx-serve.sh` if needed): port `8080`, max tokens `8192`, thinking mode off, prefix caching on, auto tool-call parser.

**Speed tips:** keep launchd server running; fresh OpenCode session for long tasks; disable unused MCPs; optional pre-warm: `curl http://127.0.0.1:8080/v1/models`.

Weights cache: `~/.cache/huggingface/hub/` (old models pruned automatically on install/upgrade).

Every `./scripts/install.sh --upgrade` runs a **model check** against HuggingFace and `config/recommended-models.json` (ranked for **M4 Pro 24 GB** agent use):

- **Current model** — Hub revision date and whether your pinned digest is stale (same model id, newer weights)
- **Recommended** — best catalog entry that fits the 12 GB RAM budget (Qwen3-8B-4bit is the default pick today)
- **Watch** — polls Hub for models in `watch` inside `config/recommended-models.json` (currently `Qwen/Qwen3.6-9B` and `mlx-community/Qwen3.6-9B-4bit`); flags the moment either lands and auto-recommends it when available
- **New on Hub** — Qwen3.5/3.6 models not yet in the catalog (hint to update rankings when mlx-community ships new sizes)

If output says a better model is available:

```bash
./scripts/install.sh --upgrade --best-model
```

That switches `PRIMARY_MODEL`, downloads weights, and re-applies the stack. To pin a specific model manually: `PRIMARY_MODEL=mlx-community/... ./scripts/install.sh --upgrade`.

Edit rankings in `config/recommended-models.json` when you want to adopt new Hub models.

---

## Upgrade

```bash
./scripts/install.sh --upgrade
```

One command upgrades Python deps, OpenCode, model weights, restarts the server, re-applies OpenCode config, cleans unused HF caches, runs a **model check**, and **verify**. Output shows **Before**, per-component `(unchanged)` or `before → after`, then **After**.

If anything breaks (wrong provider, stale config, server down): run `--upgrade` again.

---

## OpenCode config

Written by `install.sh` / `--upgrade`:

- **Provider:** `mlx` → `http://127.0.0.1:8080/v1`
- **Agent:** `build`, `tool_call: true`
- **Permissions:** read/grep/websearch allowed; edit/bash/write require approval
- **Timeout:** 10 min per turn

Optional MCP stubs (GitHub, Context7, Sentry) in `opencode.json.example` — all disabled by default. Fewer MCPs = faster turns.

Project-level `opencode.json` (optional) merges with global config — e.g. Foundry MCP stub in this repo.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| MLX API down | `./scripts/mlx-serve.sh status` → `restart` or `./scripts/install.sh --upgrade` |
| OpenCode "cannot connect" | Server not up yet — wait 30–90s after restart, or `./scripts/mlx-serve.sh status` |
| Wrong model / config | `./scripts/install.sh --upgrade` |
| Slow first prompt | Normal — cold load into unified memory |
| Out of memory | `PRIMARY_MODEL=mlx-community/Qwen3-8B-4bit ./scripts/install.sh --upgrade` |
| HuggingFace rate limits | `export HF_TOKEN=hf_...` then `--upgrade` |
| pip / venv broken | `rm -rf .venv && ./scripts/install.sh` |

Logs: `./scripts/mlx-serve.sh logs`

---

## Success checklist

- [ ] `./scripts/install.sh` completes (includes verify)
- [ ] `./scripts/mlx-serve.sh status` → API up, model listed
- [ ] `opencode` connects and uses tools (read files, run approved commands)
