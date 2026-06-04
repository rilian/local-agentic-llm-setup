# Goal: Local Agentic LLM (Mac M4 Pro)

## Summary

**Terminal-first** local coding agent (Ollama + OpenCode + `/loop` script). **ChatGPT** for general GUI chat. **VS Code + Roo Code** optional — last step, manual plugin install.

---

## Setup automation summary

| Step | What | Automatic? | How |
|------|------|------------|-----|
| 0 | Homebrew | Manual once | [brew.sh](https://brew.sh) if missing |
| 1 | Ollama + service | **Yes** | `./scripts/install.sh` or `brew install ollama` |
| 2 | Download model (~18 GB) | **Yes** (slow) | script runs `ollama pull` — wait 15–30 min |
| 3 | OpenCode CLI | **Yes** | `./scripts/install.sh` |
| 4 | OpenCode → Ollama config | **Yes** | script copies `config/opencode.json.example` |
| 5 | Terminal daily use | **You run** | `opencode --dangerously-skip-permissions` |
| 6 | `/loop` long tasks | **You run** | `./scripts/loop.sh "task"` |
| 7 | Pin model version | **Yes** | script creates `config/models.env` |
| **8** | **VS Code + Roo Code** | **Manual** | Marketplace install + UI settings — [SETUP.md Step 8](docs/SETUP.md) |

**One command for Steps 1–4 and 7:**

```bash
cd /path/to/local-agentic-llm-setup
chmod +x scripts/install.sh
./scripts/install.sh
```

Cannot be fully hands-off: model download time, first-time brew, and **Step 8 require you**.

---

## Constraints

- Terminal agent: OpenCode + `scripts/loop.sh` (`/loop`)
- Shell access: npm, bash, dev servers
- Privacy-first, local Ollama
- GUI: ChatGPT (general) · Roo Code in VS Code (optional, Step 8)

---

## Hardware

MacBook Pro M4 Pro, 24 GB RAM, ~296 GB free disk.

**Primary model:** `qwen3-coder:30b` (or `qwen3-coder-64k` after Modelfile)

Full guide: **[docs/SETUP.md](docs/SETUP.md)**

---

## Success criteria

- [ ] `./scripts/install.sh` completes without errors
- [ ] `ollama list` shows coding model
- [ ] `opencode run --dangerously-skip-permissions "hello"` works
- [ ] `./scripts/loop.sh "small test"` → `LOOP_COMPLETE`
- [ ] **(Optional Step 8)** Roo Code in VS Code connected to Ollama
