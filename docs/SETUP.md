# Full Setup: Local Agentic LLM with MLX (Mac M4 Pro)

Terminal-first agent: **OpenCode** + **native MLX** (`mlx-lm` server) + **`./scripts/loop.sh`**. **ChatGPT** for general GUI chat.

**Hardware:** MacBook Pro M4 Pro, 24 GB RAM.

**Stack:** Models run on Apple MLX via an OpenAI-compatible API at `http://127.0.0.1:8080/v1`.

---

## Can everything be done automatically?

| Step | Task | Automatic? | Notes |
|------|------|------------|-------|
| **0** | Install Homebrew | Manual once | Only if not already installed |
| **1** | Python venv + mlx-lm | ✅ Yes | `scripts/install.sh` |
| **2** | Download Qwen3.5 9B MLX | ✅ Yes, **~10–20 min** | ~7 GB from HuggingFace |
| **3** | MLX server (launchd) | ✅ Yes | `scripts/mlx-serve.sh` |
| **4** | Install OpenCode CLI | ✅ Yes | `install.sh` |
| **5** | Wire OpenCode → MLX | ✅ Yes | tool_call, timeout, permissions |
| **5b** | Web search env | ✅ Yes | `OPENCODE_ENABLE_EXA=1` in `~/.zshrc` |
| **6** | Use terminal agent | You run | `opencode` — approve each action |
| **7** | `/loop` long tasks | You run | `./scripts/loop.sh "…"` |
| **8** | Pin model in repo | ✅ Yes | `config/models.env` |

### One-command setup

```bash
git clone <this-repo> ~/local-agentic-llm-setup   # if needed
cd ~/local-agentic-llm-setup
chmod +x scripts/install.sh scripts/loop.sh scripts/mlx-serve.sh
./scripts/install.sh
```

| Command | Purpose |
|---------|---------|
| `./scripts/install.sh` | Full install (new machine) |
| `./scripts/install.sh --verify` | Verify setup (~15s) |
| `./scripts/install.sh --repair` | Re-apply MLX server + OpenCode config |
| `./scripts/install.sh --upgrade` | Upgrade mlx-lm + OpenCode |
| `./scripts/install.sh --benchmark` | Run speed/quality benchmarks |
| `./scripts/install.sh --upgrade-models` | Re-download model weights |
| `./scripts/install.sh --cleanup` | Remove unused HuggingFace cache |
| `./scripts/install.sh --check` | Check for updates |
| `./scripts/mlx-serve.sh start\|stop\|status\|logs` | Manage MLX server |

**What still needs you:**

1. Homebrew absent → install from [brew.sh](https://brew.sh) first
2. Model download → wait (network + disk)
3. First inference → model loads into RAM (~30–90s)

---

## Architecture

```
  Terminal
  ├── opencode
  └── ./scripts/loop.sh
            │
            ▼
  mlx-lm server :8080/v1  ←  mlx-community/Qwen3.5-9B-OptiQ-4bit
  (Apple MLX, launchd)
```

Use VS Code as your editor; run OpenCode in the integrated terminal (`cd project && opencode`).

---

## Step 0: Homebrew (if missing)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Skip if `brew --version` works.

---

## Steps 1–8: Automated (`./scripts/install.sh`)

The install script:

1. Creates `.venv` and installs `mlx`, `mlx-lm`, `huggingface_hub`
2. Downloads `mlx-community/Qwen3.5-9B-OptiQ-4bit` (~8 GB)
3. Installs a launchd agent (`ai.local.mlx-server`) on port 8080
4. Installs OpenCode CLI
5. Writes `~/.config/opencode/opencode.json` (MLX provider)
6. Sets `OPENCODE_ENABLE_EXA=1` in `~/.zshrc`
7. Creates `config/models.env`

### Manual equivalent

<details>
<summary>Expand if you prefer running commands yourself</summary>

```bash
brew install python node
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# Download model
.venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('mlx-community/Qwen3.5-9B-OptiQ-4bit')"

# Start MLX server
./scripts/mlx-serve.sh start

# OpenCode
brew install anomalyco/tap/opencode
cp opencode.json.example ~/.config/opencode/opencode.json

# Verify
./scripts/install.sh --verify
```

</details>

---

## Choosing a model (Qwen3.5 9B OptiQ MLX)

| Model | Size | RAM | Role |
|-------|------|-----|------|
| `mlx-community/Qwen3.5-9B-OptiQ-4bit` | ~7 GB | ~9 GB | **Default** |

To use a different MLX model:

```bash
PRIMARY_MODEL=mlx-community/Qwen3-8B-4bit ./scripts/install.sh --repair
```

See [MODELS.md](MODELS.md) for alternatives.

---

## Daily use

```bash
source ~/.zshrc          # once per terminal session
./scripts/mlx-serve.sh status   # confirm API is up
opencode                 # start agent (approval-only)
```

Switch model in session: `/models` in the OpenCode TUI.

Quality/long task:

```bash
./scripts/loop.sh "Refactor auth module — LOOP_COMPLETE when tests pass"
```

---

## Step 5b: Attach MCP servers (optional)

OpenCode supports MCP servers for GitHub, Sentry, Context7, etc. Edit `~/.config/opencode/opencode.json` or use `opencode mcp add`.

The template in `opencode.json.example` includes disabled MCP stubs. Enable and set env vars as needed.

**Tip:** Fewer enabled MCPs = faster turns. Disable unused MCPs for daily coding.

---

## OpenCode config essentials

The install script sets:

- **Provider:** `mlx` → `http://127.0.0.1:8080/v1`
- **Model:** `mlx/mlx-community/Qwen3.5-9B-OptiQ-4bit`
- **Agent:** `build` with `tool_call: true`
- **Permissions:** read/grep/websearch allowed; edit/bash/write require approval
- **Timeout:** 600000 ms (10 min) for long agent turns

Thinking mode is disabled server-side (`enable_thinking: false`) for faster, direct replies.

---

## Troubleshooting

### MLX API not responding

```bash
./scripts/mlx-serve.sh status
./scripts/mlx-serve.sh logs
./scripts/mlx-serve.sh restart
```

First start after download loads weights into RAM — can take 30–90 seconds before chat works.

### OpenCode can't reach model

1. Confirm API: `curl http://127.0.0.1:8080/v1/models`
2. Re-apply config: `./scripts/install.sh --repair`
3. Model ID in OpenCode must match server: `mlx-community/Qwen3.5-9B-OptiQ-4bit`

### Slow first prompt

Normal — cold load loads ~8 GB into unified memory. Subsequent prompts are much faster.

### Out of memory

Use a smaller model:

```bash
PRIMARY_MODEL=mlx-community/Qwen3-8B-4bit ./scripts/install.sh --repair
```

### HuggingFace rate limits

Set a token for faster downloads:

```bash
export HF_TOKEN=hf_...   # https://huggingface.co/settings/tokens
./scripts/install.sh --upgrade-models
```

---

## Verification

```bash
./scripts/install.sh --verify
VERIFY_INFERENCE=1 ./scripts/install.sh --verify   # includes live chat test
```

Expected:

- MLX API on `:8080`
- LaunchAgent loaded
- OpenCode config with MLX provider + tool_call
- Optional: inference returns "setup ok"

---

## Quick reference

| Task | Command |
|------|---------|
| Start agent | `opencode` |
| Long task | `./scripts/loop.sh "task"` |
| Server status | `./scripts/mlx-serve.sh status` |
| Restart server | `./scripts/mlx-serve.sh restart` |
| Re-verify | `./scripts/install.sh --verify` |
| Benchmark | `./scripts/install.sh --benchmark` |
| Upgrade | `./scripts/install.sh --upgrade` |

See also: [MODELS.md](MODELS.md) · [UPGRADING.md](UPGRADING.md) · [BENCHMARKS.md](BENCHMARKS.md)
