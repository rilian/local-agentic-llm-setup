# Optional: VS Code + Zoo Code (local Ollama)

**Not required.** The primary agent for this repo is **OpenCode in the terminal** — see [SETUP.md](SETUP.md).

Use this guide only if you want a VS Code sidebar chat connected to the same local Ollama stack.

**Prerequisite:** Complete [SETUP.md](SETUP.md) Steps 0–7 first (`./scripts/install.sh`). Ollama must be running on `http://127.0.0.1:11434`.

---

## Zoo Code vs OpenCode

| | OpenCode (primary) | Zoo Code (optional) |
|--|-------------------|---------------------|
| Where | Terminal (`opencode`) | VS Code sidebar |
| Tool calling | Reliable with local 30B | Often timeouts / loops |
| Best for | Agent work, MCP, `/loop` | Ask-mode chat only |
| Setup | [SETUP.md](SETUP.md) | This file |

Local **Zoo Code Architect/Code modes** often hit `fetch failed` or tool loops with Ollama 30B. Pre-warm the model and use **Ask mode**, or skip Zoo Code entirely.

---

## Install VS Code (if needed)

Download from [code.visualstudio.com](https://code.visualstudio.com) or:

```bash
brew install --cask visual-studio-code
```

---

## Install Zoo Code extension

> **Roo Code is sunset (May 2026).** Use **[Zoo Code](https://marketplace.visualstudio.com/items?itemName=ZooCodeOrganization.zoo-code)** — community fork with active development. Roo → Zoo: [migration guide](https://docs.zoocode.dev/roo-to-zoo-migration). **Alternative:** [Cline](https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev).

1. Open **Visual Studio Code**
2. **Extensions** (`Cmd+Shift+X`)
3. Search **Zoo Code**
4. Install **Zoo Code** (publisher: **Zoo Code Organization**)
5. Click the **Zoo Code** icon in the left activity bar

CLI install (optional):

```bash
code --install-extension ZooCodeOrganization.zoo-code
```

---

## Connect Zoo Code to local Ollama

1. Open Zoo Code panel → **gear icon** (Provider Settings)
2. Set:

   | Setting | Value |
   |---------|-------|
   | **API Provider** | `Ollama` |
   | **Base URL** | `http://localhost:11434` |
   | **Model ID** | Exact name from `ollama list` — e.g. `qwen3-coder:30b` (32k ctx) |

3. Click **Save**
4. **No API key** required

**Test** (Ask mode): `What model are you using? Reply in one sentence.`

If it errors:

```bash
curl http://127.0.0.1:11434/api/tags
ollama list
brew services start ollama   # if not running
```

Common fixes:

- Wrong model ID → must match `ollama list` exactly
- Use `http://localhost:11434` not `https://`
- **`fetch failed`** → see below

---

## `fetch failed` troubleshooting

If Zoo Code **reads files** but then errors with `"details": "fetch failed"` (provider: ollama), Ollama is usually fine — the **HTTP request from VS Code timed out** before the 30B model finished loading or processing a large prompt.

Typical on the **first request** when the model is cold (~1 min load) plus Architect/Code mode sends a huge prompt.

**Fix (do all three):**

1. **Pre-warm the model:**

   ```bash
   ollama run qwen3-coder:30b "hi"
   ollama ps   # CONTEXT should show 32768
   ```

2. **Increase timeout** — this repo sets 900s in `.vscode/settings.json`:

   ```json
   "roo-cline.apiRequestTimeout": 900
   ```

   Reload VS Code after changing. Set `0` for no timeout (local only).

3. **Use Ask mode** for chat. Use **OpenCode** in the terminal for agent work.

**Quick test** (after pre-warm, Ask mode): `Reply in one sentence: what model are you?`

**Faster model in Zoo:** `qwen3-coder:14b` (installed by `./scripts/install.sh`).

---

## Manual approval (required)

Keep **Auto Approve (BRRR) disabled**. Approve each Read / Write / Execute action in the sidebar.

This repo's `.vscode/settings.json` lists common allowed shell commands (`npm`, `git`, `bash`, etc.) via `roo-cline.allowedCommands`. Zoo Code still asks before running them.

---

## `/loop` in Zoo Code (optional)

Zoo Code uses `.roo/commands/` (Roo Code legacy path). This repo includes [.roo/commands/loop.md](../.roo/commands/loop.md).

1. Zoo Code chat → type `/`
2. Select **`loop`**
3. Example:

```
/loop Add unit tests for the auth module, run npm test, fix failures. LOOP_COMPLETE when done.
```

For reliable long tasks, prefer `./scripts/loop.sh` in the terminal ([SETUP.md Step 6](SETUP.md#step-6-loop-long-tasks)).

---

## Verification checklist

- [ ] Zoo Code responds using local model (no cloud API key)
- [ ] `ollama list` model name matches Zoo Code **Model ID**
- [ ] Ask-mode test works after pre-warming model
- [ ] (Optional) `/loop` appears in slash command list

---

## Quick reference

| Item | Value |
|------|-------|
| Extension | `ZooCodeOrganization.zoo-code` |
| Ollama API | `http://localhost:11434` |
| Model ID | `qwen3-coder:30b` |
| Timeout setting | `roo-cline.apiRequestTimeout` in `.vscode/settings.json` |
| Allowed commands | `roo-cline.allowedCommands` in `.vscode/settings.json` |
| Base Ollama setup | [SETUP.md](SETUP.md) |
