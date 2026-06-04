# Full Setup: Local Agentic LLM (Mac M4 Pro)

Terminal-first agent (**OpenCode** + **`./scripts/loop.sh`**). **ChatGPT** for general GUI. **VS Code + Zoo Code** is the optional **last step** (manual).

**Hardware:** MacBook Pro M4 Pro, 24 GB RAM.

---

## Can everything be done automatically?

| Step | Task | Automatic? | Notes |
|------|------|------------|-------|
| **0** | Install Homebrew | Manual once | Only if not already installed |
| **1** | Install Ollama + start service | ✅ Yes | `scripts/install.sh` |
| **2** | Pull coding model (~18 GB) | ✅ Yes, **~20–30 min** | Mostly download time (~22 min on M4 Pro) |
| **2b** | Fix `llama-server` (brew) | ✅ Yes | Script installs `llama.cpp` + symlink — **required for GGUF** |
| **3** | Install OpenCode CLI | ✅ Yes | `scripts/install.sh` |
| **4** | Wire OpenCode → Ollama | ✅ Yes | Copies `config/opencode.json.example` |
| **5** | Use terminal agent | You run | `opencode` — approve each action |
| **6** | `/loop` long tasks | You run | `./scripts/loop.sh "…"` |
| **7** | Pin model in repo | ✅ Yes | Creates `config/models.env` |
| **8** | VS Code + Zoo Code | ❌ **Manual** | Marketplace + UI clicks — **last step** |

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
3. **Step 8** → install Zoo Code extension in VS Code by hand

**Observed on this machine (2026-06-04):** full `install.sh` ~22 min; first Ollama inference ~2 min (model load into RAM).

---

## Architecture

```
  Terminal (primary)                VS Code (optional, Step 8)
  ├── opencode                      └── Zoo Code → same Ollama API
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

### Verify Steps 1–7 (fast — no model load)

```bash
./scripts/verify.sh
```

This checks Ollama API, `llama-server` binary, models, and a **10-second runtime probe** (catches `llama-server binary not found` without waiting for the 30B model to load).

Optional full inference test (~2 min first load):

```bash
VERIFY_INFERENCE=1 ./scripts/verify.sh
```

Manual checks:

```bash
curl -s http://127.0.0.1:11434/api/tags | head
ollama list
opencode --version
```

If you see `llama-server binary not found`:

```bash
./scripts/fix-llama-server.sh
./scripts/verify.sh
```

Do **not** use `ollama run … "setup ok"` as a quick test — the 30B model takes ~2 min to load on first run. Use `./scripts/verify.sh` instead.

---

## Approval-only policy

This setup **never** uses `--dangerously-skip-permissions`. You approve every file edit and shell command.

| Tool | How approvals work |
|------|-------------------|
| **OpenCode TUI** | Run `opencode` → approve/deny each tool call in the UI |
| **OpenCode one-shot** | `opencode run -i "…"` → same prompts in split-footer mode |
| **loop.sh** | Uses `opencode run -i` each iteration — stay at the terminal to approve |
| **Zoo Code** | Leave **Auto Approve (BRRR)** **off** — approve Read / Write / Execute per action |

Do **not** pass `--dangerously-skip-permissions` and do **not** enable Zoo Code BRRR auto-approve unless you explicitly want to override this policy later.

## Step 5: Daily terminal use

```bash
cd /path/to/your/project
opencode
```

Approve each file edit and shell command when OpenCode asks.

One-shot (interactive — you approve tool use):

```bash
opencode run -i "Run npm test and summarize"
```

Chat-only (no tools, no approval needed):

```bash
opencode run "Explain what this repo does in one paragraph"
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

Each iteration runs `opencode run -i` — **stay at the terminal** and approve actions as they appear. Uses [prompts/loop.md](../prompts/loop.md). In VS Code (Step 8), use `/loop` from [.roo/commands/loop.md](../.roo/commands/loop.md) and approve each Zoo Code action.

---

## Step 8: VS Code + Zoo Code (manual — do this last)

Do this **after** Steps 1–7 work. Ollama must already be running on `http://127.0.0.1:11434`.

> **Roo Code is sunset (May 2026).** The original Roo Code extension still works but receives no updates. This guide uses **[Zoo Code](https://marketplace.visualstudio.com/items?itemName=ZooCodeOrganization.zoo-code)** — a community fork with active development and the same Ollama/local setup. If you already use Roo Code, see the [Roo → Zoo migration guide](https://docs.zoocode.dev/roo-to-zoo-migration). **Alternative:** [Cline](https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev) (where Roo Code originated).

### 8a. Install VS Code (if needed)

Download from [code.visualstudio.com](https://code.visualstudio.com) or:

```bash
brew install --cask visual-studio-code
```

### 8b. Install Zoo Code extension (manual)

1. Open **Visual Studio Code**
2. **Extensions** (`Cmd+Shift+X`)
3. Search **Zoo Code**
4. Install **Zoo Code** (publisher: **Zoo Code Organization**)
5. Click the **Zoo Code** icon in the left activity bar

CLI install (optional):

```bash
code --install-extension ZooCodeOrganization.zoo-code
```

Cannot be automated — VS Code Marketplace requires a click in the editor (unless using CLI above).

### 8c. Connect Zoo Code to your local Ollama

1. Open Zoo Code panel → click the **gear icon** (Provider Settings)
2. Set:

   | Setting | Value |
   |---------|-------|
   | **API Provider** | `Ollama` |
   | **Base URL** | `http://localhost:11434` |
   | **Model ID** | Exact name from `ollama list` — e.g. `qwen3-coder-64k` or `qwen3-coder:30b` |

3. Click **Save** / close settings
4. **No API key** required for local Ollama

**Test:** in Zoo Code chat, send `What model are you using? Reply in one sentence.`

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

### 8d. Manual approval (required)

Keep **Auto Approve (BRRR) disabled**. Approve each action in the Zoo Code sidebar:

1. When Zoo Code wants to read, write, or run a command → review the diff or command → **Approve** or **Reject**
2. For shell commands, this repo's `.vscode/settings.json` lists common allowed commands (`npm`, `git`, `bash`, etc.) — Zoo Code still asks before running them unless you later enable auto-approve yourself
3. Long `/loop` tasks work fine with manual approval; they just take more clicks

### 8e. Use `/loop` in Zoo Code (optional)

Zoo Code uses the same `.roo/commands/` folder as Roo Code (inherited from the fork). Open a workspace that contains `.roo/commands/loop.md` (this repo, or copy that file to your project).

1. Zoo Code chat → type `/`
2. Select **`loop`**
3. Example:

```
/loop Add unit tests for the auth module, run npm test, fix failures. LOOP_COMPLETE when done.
```

Approve each file edit and `npm` command when Zoo Code prompts.

### Step 8 verification

- [ ] Zoo Code responds using local model (no cloud API key)
- [ ] `ollama list` model name matches Zoo Code **Model ID**
- [ ] Agent can edit a file from Zoo Code sidebar
- [ ] (Optional) `/loop` appears in slash command list

---

## Updating models

```bash
ollama pull qwen3-coder:30b
ollama rm old-tag
```

Update:

- `~/.config/opencode/opencode.json` → `"model"` field
- Zoo Code settings → Model ID
- `config/models.env`

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `llama-server binary not found` | `./scripts/fix-llama-server.sh` then `./scripts/verify.sh` |
| Ollama not running | `brew services start ollama` |
| First inference ~2 min | Normal — 30B model loading into RAM |
| OpenCode permission prompts | Expected — approve or deny in the UI; never use `--dangerously-skip-permissions` |
| Zoo Code can't connect | Check Base URL + model ID vs `ollama list` |
| Zoo Code asks approve every action | Expected with approval-only policy (Step 8d) |
| Loop stops early | `./scripts/loop.sh --max 50 "…"` or `--continue` in opencode |

### `llama-server binary not found` (Homebrew Ollama 0.30+)

Homebrew Ollama does not bundle `llama-server`; GGUF models fail without this fix.

**One command:**

```bash
./scripts/fix-llama-server.sh
./scripts/verify.sh
```

**Manual equivalent:**

```bash
brew install llama.cpp
OLLAMA_VER=$(ollama --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
BREW_PREFIX=$(brew --prefix)
mkdir -p "${BREW_PREFIX}/Cellar/ollama/${OLLAMA_VER}/libexec/lib/ollama"
ln -sf "$(which llama-server)" "${BREW_PREFIX}/Cellar/ollama/${OLLAMA_VER}/libexec/lib/ollama/llama-server"
brew services restart ollama   # required — daemon must restart to pick up the binary
```

Re-run after `brew upgrade ollama`. **Alternative:** use [Ollama.app](https://ollama.com/download) instead of brew.

---

## Quick reference

| Item | Value |
|------|-------|
| Auto install | `./scripts/install.sh` |
| Fast verify | `./scripts/verify.sh` |
| Fix llama-server | `./scripts/fix-llama-server.sh` |
| Ollama API | `http://127.0.0.1:11434` |
| Terminal agent | `opencode` (approve each action) |
| Long task (terminal) | `./scripts/loop.sh "…"` |
| Long task (VS Code) | `/loop …` in Zoo Code |
| OpenCode config | `~/.config/opencode/opencode.json` |
| Zoo Code allowed cmds | `.vscode/settings.json` (`roo-cline.*` keys) |
| Last manual step | **Step 8 — Zoo Code extension** |

---

## Checklist (in order)

- [ ] Step 0: Homebrew installed
- [ ] Steps 1–7: `./scripts/install.sh` succeeded
- [ ] Fast verify: `./scripts/verify.sh`
- [ ] **Step 8:** Zoo Code installed + connected to Ollama
- [ ] [GOAL.md](../GOAL.md) success criteria
