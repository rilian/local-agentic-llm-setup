# Full Setup: Local Agentic LLM (Mac M4 Pro)

Terminal-first agent (**OpenCode** + **`./scripts/loop.sh`**). **ChatGPT** for general GUI. **VS Code + Roo Code** is the optional **last step** (manual).

**Hardware:** MacBook Pro M4 Pro, 24 GB RAM.

---

## Can everything be done automatically?

| Step | Task | Automatic? | Notes |
|------|------|------------|-------|
| **0** | Install Homebrew | Manual once | Only if not already installed |
| **1** | Install Ollama + start service | ✅ Yes | `scripts/install.sh` |
| **2** | Pull coding model (~18 GB) | ✅ Yes, **slow** | 15–30 min download; script waits |
| **3** | Install OpenCode CLI | ✅ Yes | `scripts/install.sh` |
| **4** | Wire OpenCode → Ollama | ✅ Yes | Copies `config/opencode.json.example` |
| **5** | Use terminal agent | You run | `opencode --dangerously-skip-permissions` |
| **6** | `/loop` long tasks | You run | `./scripts/loop.sh "…"` |
| **7** | Pin model in repo | ✅ Yes | Creates `config/models.env` |
| **8** | VS Code + Roo Code | ❌ **Manual** | Marketplace + UI clicks — **last step** |

### One-command automated setup (Steps 1–4, 7)

```bash
git clone <this-repo> ~/local-agentic-llm-setup   # if needed
cd ~/local-agentic-llm-setup
chmod +x scripts/install.sh scripts/loop.sh
./scripts/install.sh
```

Optional env vars:

```bash
PULL_FAST=1 ./scripts/install.sh      # also pull qwen3-coder:14b
CREATE_64K=0 ./scripts/install.sh     # skip 64k Modelfile variant
PRIMARY_MODEL=qwen3-coder:14b ./scripts/install.sh   # smaller/faster model
```

An agent (or you) **can** run `./scripts/install.sh` end-to-end. What still needs **you**:

1. Homebrew absent → install from brew.sh first
2. Model download → wait (network + disk)
3. **Step 8** → install Roo Code extension in VS Code by hand

---

## Architecture

```
  Terminal (primary)                VS Code (optional, Step 8)
  ├── opencode                      └── Roo Code → same Ollama API
  └── ./scripts/loop.sh
            │
            ▼
     Ollama :11434  ←  qwen3-coder:30b / qwen3-coder-64k
```

---

## Step 0: Homebrew (if missing)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Skip if `brew --version` works.

---

## Steps 1–7: Automated (`./scripts/install.sh`)

The install script performs:

1. `brew install ollama` + `brew services start ollama`
2. `ollama pull qwen3-coder:30b`
3. `ollama create qwen3-coder-64k` (64K context Modelfile)
4. `brew install anomalyco/tap/opencode` (or curl installer fallback)
5. Copy `config/opencode.json.example` → `~/.config/opencode/opencode.json`
6. Copy `config/models.env.example` → `config/models.env`
7. `chmod +x scripts/loop.sh`

### Manual equivalent (same steps)

<details>
<summary>Expand if you prefer running commands yourself</summary>

```bash
brew install ollama node
brew services start ollama

ollama pull qwen3-coder:30b
ollama pull qwen3-coder:14b   # optional

# 64k context (recommended for OpenCode)
cat > /tmp/Modelfile <<'EOF'
FROM qwen3-coder:30b
PARAMETER num_ctx 65536
EOF
ollama create qwen3-coder-64k -f /tmp/Modelfile

brew install anomalyco/tap/opencode
mkdir -p ~/.config/opencode
cp config/opencode.json.example ~/.config/opencode/opencode.json
# set "model": "ollama/qwen3-coder-64k" in opencode.json

cp config/models.env.example config/models.env
chmod +x scripts/loop.sh
```

</details>

### Verify Steps 1–7

```bash
curl -s http://127.0.0.1:11434/api/tags | head
ollama list
opencode --version
opencode run --dangerously-skip-permissions "Reply with exactly: setup ok"
./scripts/loop.sh "Create file SETUP_OK.txt containing ok. Output LOOP_COMPLETE when done."
```

---

## Step 5: Daily terminal use

```bash
cd /path/to/your/project
opencode --dangerously-skip-permissions
```

One-shot:

```bash
opencode run --dangerously-skip-permissions "Run npm test and summarize"
```

Guided first launch (alternative to manual config):

```bash
ollama launch opencode
```

---

## Step 6: `/loop` long tasks

```bash
./scripts/loop.sh "Refactor auth: npm install, tests, README — LOOP_COMPLETE when done"
./scripts/loop.sh --max 40 "larger task"
```

Uses [prompts/loop.md](../prompts/loop.md). In VS Code (Step 8), use `/loop` from [.roo/commands/loop.md](../.roo/commands/loop.md).

---

## Step 8: VS Code + Roo Code (manual — do this last)

Do this **after** Steps 1–7 work. Ollama must already be running on `http://127.0.0.1:11434`.

### 8a. Install VS Code (if needed)

Download from [code.visualstudio.com](https://code.visualstudio.com) or:

```bash
brew install --cask visual-studio-code
```

### 8b. Install Roo Code extension (manual)

1. Open **Visual Studio Code**
2. **Extensions** (`Cmd+Shift+X`)
3. Search **Roo Code**
4. Install **Roo Code** (publisher: **RooCodeInc**)
5. Click the **Roo Code** icon in the left activity bar

Cannot be automated — VS Code Marketplace requires a click in the editor.

### 8c. Connect Roo Code to your local Ollama

1. Open Roo Code panel → click the **gear icon** (Provider Settings)
2. Set:

   | Setting | Value |
   |---------|-------|
   | **API Provider** | `Ollama` |
   | **Base URL** | `http://localhost:11434` |
   | **Model ID** | Exact name from `ollama list` — e.g. `qwen3-coder-64k` or `qwen3-coder:30b` |

3. Click **Save** / close settings
4. **No API key** required for local Ollama

**Test:** in Roo Code chat, send `What model are you using? Reply in one sentence.`

If it errors:

```bash
# confirm Ollama is up
curl http://127.0.0.1:11434/api/tags
ollama list
```

Common fixes:

- Wrong model ID → must match `ollama list` exactly
- Ollama not running → `brew services start ollama`
- Use `http://localhost:11434` not `https://`

### 8d. Enable auto-approve for agent work (recommended)

Long tasks need uninterrupted file + shell access:

1. Roo Code home → check **Auto Approve** (**BRRR**)
2. Enable **Read**, **Write**, **Execute**
3. **Execute requires allowed commands** — open this repo in VS Code so `.vscode/settings.json` loads, **or** add `*` under Settings → Auto Approve → Allowed Commands

This repo's `.vscode/settings.json` pre-allows: `npm`, `npx`, `bash`, `git`, etc.

### 8e. Use `/loop` in Roo Code (optional)

Open a workspace that contains `.roo/commands/loop.md` (this repo, or copy that file to your project).

1. Roo Code chat → type `/`
2. Select **`loop`**
3. Example:

```
/loop Add unit tests for the auth module, run npm test, fix failures. LOOP_COMPLETE when done.
```

Enable BRRR (8d) so it won't stop for every file edit and `npm` command.

### Step 8 verification

- [ ] Roo Code responds using local model (no cloud API key)
- [ ] `ollama list` model name matches Roo **Model ID**
- [ ] Agent can edit a file from Roo sidebar
- [ ] (Optional) `/loop` appears in slash command list

---

## Updating models

```bash
ollama pull qwen3-coder:30b
ollama rm old-tag
```

Update:

- `~/.config/opencode/opencode.json` → `"model"` field
- Roo Code settings → Model ID
- `config/models.env`

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Ollama not running | `brew services start ollama` |
| OpenCode permission prompts | `--dangerously-skip-permissions` |
| Roo can't connect | Check Base URL + model ID vs `ollama list` |
| Roo asks approve every `npm` | Enable Execute + add allowed commands (Step 8d) |
| Loop stops early | `./scripts/loop.sh --max 50 "…"` or `--continue` in opencode |

---

## Quick reference

| Item | Value |
|------|-------|
| Auto install | `./scripts/install.sh` |
| Ollama API | `http://127.0.0.1:11434` |
| Terminal agent | `opencode --dangerously-skip-permissions` |
| Long task (terminal) | `./scripts/loop.sh "…"` |
| Long task (VS Code) | `/loop …` in Roo Code |
| OpenCode config | `~/.config/opencode/opencode.json` |
| Roo allowed cmds | `.vscode/settings.json` |
| Last manual step | **Step 8 — Roo Code extension** |

---

## Checklist (in order)

- [ ] Step 0: Homebrew installed
- [ ] Steps 1–7: `./scripts/install.sh` succeeded
- [ ] Terminal verify: `opencode run …` and `./scripts/loop.sh …`
- [ ] **Step 8:** Roo Code installed + connected to Ollama
- [ ] [GOAL.md](../GOAL.md) success criteria
