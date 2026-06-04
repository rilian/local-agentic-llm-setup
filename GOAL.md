# Goal: Local Agentic LLM (Mac M4 Pro)

## Summary

**Terminal-first** local coding agent (Ollama + OpenCode + `/loop` script). **ChatGPT** for general GUI chat. **VS Code + Zoo Code** optional — last step, manual plugin install.

---

## Setup automation summary

| Step | What | Automatic? | How |
|------|------|------------|-----|
| 0 | Homebrew | Manual once | [brew.sh](https://brew.sh) if missing |
| 1 | Ollama + service | **Yes** | `./scripts/install.sh` or `brew install ollama` |
| 2 | Download model (~18 GB) | **Yes** (slow) | script runs `ollama pull` — ~22 min observed |
| 2b | `llama-server` fix (brew) | **Yes** | `./scripts/fix-llama-server.sh` (also run from `install.sh`) |
| 3 | OpenCode CLI | **Yes** | `./scripts/install.sh` |
| 4 | OpenCode → Ollama config | **Yes** | script copies `config/opencode.json.example` |
| 5 | Terminal daily use | **You run** | `opencode` (approve each action in the UI) |
| 6 | `/loop` long tasks | **You run** | `./scripts/loop.sh "task"` |
| 7 | Pin model version | **Yes** | script creates `config/models.env` |
| **8** | **VS Code + Zoo Code** | **Manual** | Marketplace install + UI settings — [SETUP.md Step 8](docs/SETUP.md) |

**One command for Steps 1–4 and 7:**

```bash
cd /path/to/local-agentic-llm-setup
chmod +x scripts/install.sh
./scripts/install.sh
```

Cannot be fully hands-off: model download time, first-time brew, and **Step 8 require you**.

**Install run 2026-06-04:** Steps 1–7 completed; models `qwen3-coder:30b` + `qwen3-coder-64k` installed. Hit brew `llama-server` gap — fixed via `llama.cpp` symlink (now in `install.sh`).

---

## Constraints

- Terminal agent: OpenCode + `scripts/loop.sh` (`/loop`)
- Shell access: npm, bash, dev servers
- Privacy-first, local Ollama
- **Approval-only:** never use `--dangerously-skip-permissions`; approve file edits and shell commands yourself
- GUI: ChatGPT (general) · Zoo Code in VS Code (optional, Step 8)

---

## Hardware

MacBook Pro M4 Pro, 24 GB RAM, ~296 GB free disk.

**Primary model:** `qwen3-coder:30b` (or `qwen3-coder-64k` after Modelfile)

Full guide: **[docs/SETUP.md](docs/SETUP.md)**

---

## Success criteria

- [ ] `./scripts/install.sh` completes without errors
- [ ] `ollama list` shows coding model
- [ ] `./scripts/verify.sh` passes (fast)
- [ ] Optional: `VERIFY_INFERENCE=1 ./scripts/verify.sh` after first model load
- [ ] **(Optional Step 8)** Zoo Code in VS Code connected to Ollama
