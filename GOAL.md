# Goal: Local Agentic LLM (Mac M4 Pro)

## Summary

**Terminal-first** local coding agent (Ollama + OpenCode + `/loop` script). **ChatGPT** for general GUI chat.

Optional VS Code sidebar: [docs/setup-zoocode.md](docs/setup-zoocode.md) — not required.

---

## Setup automation summary

**Single entry point:** `./scripts/install.sh` — install, verify, upgrade, and repair are all built in.

| Step | What | Automatic? | How |
|------|------|------------|-----|
| 0 | Homebrew | Manual once | [brew.sh](https://brew.sh) if missing |
| 1 | Ollama + service | **Yes** | `./scripts/install.sh` |
| 2 | Download models (30b + 14b) | **Yes** (slow) | `install.sh` |
| 2b | `llama-server` fix | **Yes** | built into `install.sh` |
| 2c | Ollama context 32k | **Yes** | built into `install.sh` |
| 3 | OpenCode CLI | **Yes** | `install.sh` |
| 4 | OpenCode → Ollama config | **Yes** | built into `install.sh` |
| 4b | Web search shell env | **Yes** | built into `install.sh` |
| 5 | Terminal daily use | **You run** | `opencode` |
| 5b | MCP servers | **You configure** | [SETUP.md Step 5b](docs/SETUP.md) |
| 6 | `/loop` long tasks | **You run** | `./scripts/loop.sh "task"` |
| 7 | Pin model version | **Yes** | `install.sh` → `config/models.env` |

```bash
cd /path/to/local-agentic-llm-setup
chmod +x scripts/install.sh scripts/loop.sh
./scripts/install.sh
```

| Command | Purpose |
|---------|---------|
| `./scripts/install.sh --verify` | Verify (~15s) |
| `./scripts/install.sh --repair` | Re-apply fixes |
| `./scripts/install.sh --upgrade` | Upgrade stack |
| `./scripts/install.sh --upgrade-models` | Re-pull Qwen models |
| `./scripts/install.sh --check` | Check for updates |

---

## Constraints

- Terminal agent: OpenCode + `scripts/loop.sh` (`/loop`)
- Shell access: npm, bash, dev servers
- Privacy-first, local Ollama
- **Approval-only:** never use `--dangerously-skip-permissions`
- GUI chat: ChatGPT (general)

---

## Hardware

MacBook Pro M4 Pro, 24 GB RAM, ~296 GB free disk.

**Primary model:** `qwen3-coder:30b` at **32k context** · **Fast model:** `qwen3-coder:14b` (both installed by `install.sh`)

Full guide: **[docs/SETUP.md](docs/SETUP.md)**

---

## Success criteria

- [ ] `./scripts/install.sh` completes without errors
- [ ] `./scripts/install.sh --verify` passes
- [ ] `ollama ps` → CONTEXT 32768 (not 4096) after first request
- [ ] OpenCode tool test: reads a file via tool, not prose
