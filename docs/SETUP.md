# Full Setup: Local Agentic LLM (Mac M4 Pro)

Terminal-first agent: **OpenCode** + **`./scripts/loop.sh`**. **ChatGPT** for general GUI chat.

**Hardware:** MacBook Pro M4 Pro, 24 GB RAM.

Optional VS Code sidebar agent (Zoo Code): [setup-zoocode.md](setup-zoocode.md) — not required.

---

## Can everything be done automatically?

| Step | Task | Automatic? | Notes |
|------|------|------------|-------|
| **0** | Install Homebrew | Manual once | Only if not already installed |
| **1** | Install Ollama + start service | ✅ Yes | `scripts/install.sh` |
| **2** | Pull coding model (~18 GB) | ✅ Yes, **~20–30 min** | Mostly download time (~22 min on M4 Pro) |
| **2b** | Fix `llama-server` (brew) | ✅ Yes | `install.sh` (built-in) |
| **2c** | Ollama context 32k (tools) | ✅ Yes | `install.sh` (built-in) |
| **3** | Install OpenCode CLI | ✅ Yes | `install.sh` |
| **4** | Wire OpenCode → Ollama | ✅ Yes | `install.sh` — tool_call, timeout, permissions |
| **4b** | Web search env | ✅ Yes | `install.sh` → `OPENCODE_ENABLE_EXA=1` in `~/.zshrc` |
| **5** | Use terminal agent | You run | `opencode` — approve each action |
| **5b** | Attach MCP servers | You configure | `opencode mcp add` or `opencode.json` — [Step 5b](#step-5b-attach-mcp-servers-optional) |
| **6** | `/loop` long tasks | You run | `./scripts/loop.sh "…"` |
| **7** | Pin model in repo | ✅ Yes | Creates `config/models.env` |

### One-command setup (new machine)

An LLM or you can run **only this**:

```bash
git clone <this-repo> ~/local-agentic-llm-setup   # if needed
cd ~/local-agentic-llm-setup
chmod +x scripts/install.sh scripts/loop.sh
./scripts/install.sh
```

**All fixes, config, and verification are built into `install.sh`.** No separate fix scripts.

| Command | Purpose |
|---------|---------|
| `./scripts/install.sh` | Full install (new machine) |
| `./scripts/install.sh --verify` | Verify setup (~15s) |
| `./scripts/install.sh --repair` | Re-apply fixes (llama-server, context, OpenCode config) |
| `./scripts/install.sh --upgrade` | Upgrade Ollama, OpenCode, models |
| `./scripts/install.sh --check` | Check for available upgrades (no changes) |

Optional env vars:

```bash
PULL_FAST=1 ./scripts/install.sh      # also pull qwen3-coder:14b
CREATE_64K=1 ./scripts/install.sh     # optional 64k Modelfile (65536 — tight on 24 GB RAM)
PRIMARY_MODEL=qwen3-coder:14b ./scripts/install.sh   # smaller/faster model
```

An agent (or you) **can** run `./scripts/install.sh` end-to-end. What still needs **you**:

1. Homebrew absent → install from brew.sh first
2. Model download → wait (network + disk)

**Observed on this machine (2026-06-04):** full `install.sh` ~22 min; first Ollama inference ~2 min (model load into RAM).

---

## Architecture

```
  Terminal
  ├── opencode
  └── ./scripts/loop.sh
            │
            ▼
     Ollama :11434  ←  qwen3-coder:30b (32k ctx default)
```

Use VS Code as your editor; run OpenCode in the integrated terminal (`cd project && opencode`).

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
2. Set `OLLAMA_CONTEXT_LENGTH=32768` and `OLLAMA_KEEP_ALIVE=-1` in launchd plist
3. `ollama pull qwen3-coder:30b`
4. `brew install anomalyco/tap/opencode` (or curl installer fallback)
5. Copy `config/opencode.json.example` → `~/.config/opencode/opencode.json` (model: `qwen3-coder:30b`)
6. Copy `config/models.env.example` → `config/models.env`
7. `chmod +x scripts/loop.sh`

Optional: `CREATE_64K=1 ./scripts/install.sh` also creates `qwen3-coder-64k` (65536 context — tight on 24 GB RAM).

### Manual equivalent (same steps)

<details>
<summary>Expand if you prefer running commands yourself</summary>

```bash
brew install ollama node
brew services start ollama

ollama pull qwen3-coder:30b
ollama pull qwen3-coder:14b   # optional

# Default: 32k context via OLLAMA_CONTEXT_LENGTH=32768 (install.sh sets this)
# Optional 64k Modelfile (tight on 24 GB RAM):
# CREATE_64K=1 ./scripts/install.sh

brew install anomalyco/tap/opencode
mkdir -p ~/.config/opencode
cp config/opencode.json.example ~/.config/opencode/opencode.json

cp config/models.env.example config/models.env
chmod +x scripts/loop.sh
```

</details>

### Verify Steps 1–7 (fast — no model load)

```bash
./scripts/install.sh --verify
```

This checks Ollama API, `llama-server` binary, **OLLAMA_CONTEXT_LENGTH=32768**, OpenCode tool config (`tool_call`, `websearch`, `task`), models, and a **10-second runtime probe**.

Optional full inference test (~2 min first load):

```bash
VERIFY_INFERENCE=1 ./scripts/install.sh --verify
```

Manual checks:

```bash
curl -s http://127.0.0.1:11434/api/tags | head
ollama list
opencode --version
```

If you see `llama-server binary not found`:

```bash
./scripts/install.sh --repair
./scripts/install.sh --verify
```

Do **not** use `ollama run … "setup ok"` as a quick test — the 30B model takes ~2 min to load on first run. Use `./scripts/install.sh --verify` instead.

---

## Approval-only policy

This setup **never** uses `--dangerously-skip-permissions`. You approve every file edit and shell command.

| Tool | How approvals work |
|------|-------------------|
| **OpenCode TUI** | Run `opencode` → approve/deny each tool call in the UI |
| **OpenCode one-shot** | `opencode run -i "…"` → same prompts in split-footer mode |
| **loop.sh** | Uses `opencode run -i` each iteration — stay at the terminal to approve |

Do **not** pass `--dangerously-skip-permissions`.

## Step 5: Daily terminal use

Open VS Code for editing, then use the integrated terminal:

```bash
cd /path/to/your/project
source ~/.zshrc    # once per session (web search)
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

### Performance tips (local 30B)

`install.sh` sets **`OLLAMA_KEEP_ALIVE=-1`** so the model stays in RAM after first use — no ~1–2 min reload when you restart `opencode`.

| Habit | Why |
|-------|-----|
| **Keep one `opencode` session open** | Avoid `Ctrl+C` — restarting loses context and may feel slow on first turn |
| **Pre-warm once per day** (optional) | `ollama run qwen3-coder:30b "hi"` before first `opencode` if the model was never loaded |
| **Focused prompts** | *"Fix auth.ts validateToken"* beats *"review entire codebase"* |
| **`@explore` for search** | Read-only subagent — less context than reading many files |
| **`qwen3-coder:14b` for quick tasks** | Switch model in OpenCode for simple edits (`PULL_FAST=1 ./scripts/install.sh`) |
| **Limit MCPs** | Disable servers you are not using — each adds tool definitions to context |

First message after a cold start is slowest (~1–2 min). After the model is warm, expect seconds to ~30s per turn.

---

## Step 5b: Attach MCP servers (optional)

OpenCode can use **Model Context Protocol (MCP)** servers — the same kind of tools you may already have in Cursor or Claude Desktop. Once attached, MCP tools appear alongside built-in tools (file edit, bash, etc.) and still require **your approval** per action.

Official reference: [OpenCode MCP docs](https://open-code.ai/en/docs/mcp-servers)

### Where config lives

| Scope | File |
|-------|------|
| **Global** (all projects) | `~/.config/opencode/opencode.json` |
| **Project** (one repo) | `./opencode.json` in project root |

Merge an `mcp` block into your existing config, or copy snippets from [config/opencode.mcp.example.json](../config/opencode.mcp.example.json).

### Option A — Interactive wizard (easiest)

```bash
opencode mcp add
```

Follow prompts for a **local** (stdio) or **remote** (URL) server.

Then verify:

```bash
opencode mcp list
opencode mcp debug my-server-name   # if connection fails
opencode mcp auth my-server-name    # OAuth servers (e.g. Sentry)
```

Restart OpenCode (`opencode` TUI) after adding servers.

### Option B — Edit `opencode.json` manually

**Local MCP** (stdio — most npm/npx servers):

```json
{
  "mcp": {
    "github": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-github"],
      "enabled": true,
      "environment": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "{env:GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    }
  }
}
```

**Remote MCP** (HTTP URL):

```json
{
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "enabled": true,
      "headers": {
        "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}"
      }
    }
  }
}
```

Use `{env:VAR_NAME}` for secrets — set them in your shell or `.env`, not in the JSON file.

### Port existing MCPs from Cursor / Claude Desktop

Cursor and Claude Desktop use `mcpServers` in JSON. OpenCode uses `mcp` with a slightly different shape:

| Cursor / Claude Desktop | OpenCode |
|-------------------------|----------|
| `"mcpServers": { "name": { … } }` | `"mcp": { "name": { … } }` |
| `"command": "npx"` + `"args": ["-y", "pkg"]` | `"command": ["npx", "-y", "pkg"]` |
| `"env": { "KEY": "val" }` | `"environment": { "KEY": "val" }` |
| `"url": "https://…"` (remote) | `"type": "remote", "url": "https://…"` |
| (implicit) | add `"type": "local"` for command-based servers |
| (implicit) | add `"enabled": true` |

**Example — Cursor `~/.cursor/mcp.json`:**

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_…"
      }
    }
  }
}
```

**Same server in OpenCode** (`~/.config/opencode/opencode.json`):

```json
{
  "mcp": {
    "github": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-github"],
      "enabled": true,
      "environment": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "{env:GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    }
  }
}
```

Export the token in your shell before starting OpenCode:

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_…"
opencode
```

### Using MCP tools in prompts

MCP tools are registered with the server name as prefix. Mention the server in your prompt:

```
List my open GitHub issues for this repo. use github
```

Or add guidance to an `AGENTS.md` in your project:

```markdown
When you need library docs, use the context7 MCP tools.
```

### Enable / disable MCP tools

Disable a server without removing config:

```json
{
  "mcp": {
    "github": { "type": "local", "command": ["…"], "enabled": false }
  }
}
```

Disable all tools from a server globally (useful when you have many MCPs):

```json
{
  "tools": {
    "github_*": false
  }
}
```

Re-enable per agent if needed — see [OpenCode MCP docs](https://open-code.ai/en/docs/mcp-servers).

### Tips for local 30B model (24 GB RAM)

- Each MCP adds tool definitions to context — **enable only what you need**
- Heavy MCPs (GitHub, large DB schemas) can crowd out code context
- Prefer 1–2 MCPs per task; disable the rest with `"enabled": false`

### Verify MCP setup

```bash
opencode mcp list          # should show your servers
cd /path/to/project && opencode
# ask: "What MCP tools do you have available?"
```

Approve MCP tool calls the same way as file edits and bash commands.

---

## Step 5c: Tools, web search, subagents (required for agent work)

If the model **chatters but never reads files, runs bash, or calls MCPs**, Ollama is almost certainly using a **4096-token context** — too small to fit tool definitions. This is the #1 local-agent failure mode.

### One-command fix (also runs automatically from `./scripts/install.sh`)

```bash
cd ~/work/local-agentic-llm-setup
./scripts/install.sh          # full install — includes all fixes below
# or re-apply fixes only:
./scripts/install.sh --repair # llama-server + context 32k
./scripts/install.sh --verify # auto-checks context, tool config, web search env
```

Add to `~/.zshrc` (done automatically by `install.sh`; only if missing):

```bash
export OPENCODE_ENABLE_EXA=1
source ~/.zshrc
```

### Verify context (must NOT be 4096)

```bash
ollama run qwen3-coder:30b "hi"    # warm the model (~2 min first time)
ollama ps                          # CONTEXT column should show 32768
```

### Verify tool calling

```bash
cd ~/work/local-agentic-llm-setup
opencode run -i "Use the read tool on GOAL.md and quote the first line verbatim"
```

You should see a **tool call** (read) and an approval prompt — not just prose about what it would do.

### Web search

Built-in `websearch` (Exa) requires `OPENCODE_ENABLE_EXA=1` when using Ollama (see above). Test:

```
Search the web for OpenCode release notes. use websearch
```

`webfetch` works for known URLs without Exa.

### Subagents

OpenCode **build** agent can delegate to subagents via the **task** tool, or you invoke them directly:

| Subagent | Use for |
|----------|---------|
| `@explore` | Read-only codebase search (grep, glob, read) |
| `@general` | General subtasks |
| `@scout` | Fast exploration |

Example:

```
@explore Find where install.sh sets up Ollama and summarize in 3 bullets
```

Subagents only work if the **primary model calls tools** — fix context first (Step 5c above).

---

## Step 6: `/loop` long tasks

```bash
./scripts/loop.sh "Refactor auth: npm install, tests, README — LOOP_COMPLETE when done"
./scripts/loop.sh --max 40 "larger task"
```

Each iteration runs `opencode run -i` — **stay at the terminal** and approve actions as they appear. Uses [prompts/loop.md](../prompts/loop.md).

---

## Updating the stack

```bash
./scripts/install.sh --upgrade          # upgrade everything + verify
./scripts/install.sh --check              # check only, no changes
SKIP_MODELS=1 ./scripts/install.sh --upgrade
OLLAMA_CONTEXT=65536 ./scripts/install.sh --upgrade   # 64k context (24 GB — tight)
```

Upgrades: Ollama, llama.cpp, OpenCode, models, re-applies llama-server + context + OpenCode config, runs `--verify`. Pins versions in `config/models.env`.

```bash
ollama pull qwen3-coder:30b
ollama rm old-tag
```

Also update `~/.config/opencode/opencode.json` → `"model"` field (or `./scripts/install.sh --repair`).

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `llama-server binary not found` | `./scripts/install.sh --repair` then `./scripts/install.sh --verify` |
| Ollama not running | `brew services start ollama` |
| First inference ~2 min | Normal — 30B model loading into RAM |
| OpenCode permission prompts | Expected — approve or deny in the UI; never use `--dangerously-skip-permissions` |
| Model talks but never uses tools | `./scripts/install.sh --repair` |
| `ollama ps` shows CONTEXT 4096 | `./scripts/install.sh --repair` |
| Web search unavailable | `export OPENCODE_ENABLE_EXA=1` before `opencode` |
| MCP server not connecting | `opencode mcp list` · `opencode mcp debug <name>` · check `command`/`url` in config |
| Loop stops early | `./scripts/loop.sh --max 50 "…"` |

### `llama-server binary not found` (Homebrew Ollama 0.30+)

Homebrew Ollama does not bundle `llama-server`; GGUF models fail without this fix.

**One command:**

```bash
./scripts/install.sh --repair
./scripts/install.sh --verify
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
| Upgrade | `./scripts/install.sh --upgrade` |
| Check updates | `./scripts/install.sh --check` |
| Verify | `./scripts/install.sh --verify` |
| Repair fixes | `./scripts/install.sh --repair` |
| Web search | `OPENCODE_ENABLE_EXA=1 opencode` |
| Ollama API | `http://127.0.0.1:11434` |
| Terminal agent | `opencode` (approve each action) |
| Long task | `./scripts/loop.sh "…"` |
| OpenCode config | `~/.config/opencode/opencode.json` |
| MCP example config | `config/opencode.mcp.example.json` |
| MCP commands | `opencode mcp add` · `opencode mcp list` |
| Optional Zoo Code | [setup-zoocode.md](setup-zoocode.md) |

---

## Checklist (in order)

- [ ] Step 0: Homebrew installed
- [ ] Steps 1–7: `./scripts/install.sh` succeeded
- [ ] Fast verify: `./scripts/install.sh --verify`
- [ ] Tool test: `opencode run -i "Use read tool on GOAL.md…"`
- [ ] [GOAL.md](../GOAL.md) success criteria
