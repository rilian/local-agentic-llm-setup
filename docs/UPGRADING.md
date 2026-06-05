# Upgrading & monitoring releases

How to keep **Ollama**, **OpenCode**, and **Qwen3 Coder** models up to date on this stack.

All commands run from the repo root:

```bash
cd ~/work/local-agentic-llm-setup
```

---

## Quick reference

| Goal | Command |
|------|---------|
| Check everything (no downloads) | `./scripts/install.sh --check` |
| Upgrade Qwen models only | `./scripts/install.sh --upgrade-models` |
| Upgrade full stack | `./scripts/install.sh --upgrade` |
| Re-apply Ollama/OpenCode fixes | `./scripts/install.sh --repair` |
| Verify after upgrade | `./scripts/install.sh --verify` |

---

## What gets upgraded

| Component | `--check` | `--upgrade-models` | `--upgrade` |
|-----------|-----------|-------------------|-------------|
| Homebrew Ollama | ✅ reports | — | ✅ if outdated |
| llama.cpp / llama-server | ✅ reports | — | ✅ if outdated |
| OpenCode CLI | ✅ reports | — | ✅ if outdated |
| `qwen3-coder:30b` | ✅ shows digest | ✅ `ollama pull` | ✅ |
| `freehuntx/qwen3-coder:14b` → alias `qwen3-coder:14b` | ✅ shows digest | ✅ pull + alias | ✅ |
| Ollama context / keep-alive plist | — | — | ✅ re-applied |
| OpenCode config | — | — | ✅ merged |
| `config/models.env` pins | ✅ shows last | ✅ updated | ✅ updated |

---

## Monitoring new Qwen releases

Ollama has no `brew outdated` for models. Watch these pages for new tags or updated dates:

| Model | Monitor |
|-------|---------|
| **30b (primary)** | [ollama.com/library/qwen3-coder/tags](https://ollama.com/library/qwen3-coder/tags) |
| **14b (fast)** | [ollama.com/freehuntx/qwen3-coder/tags](https://ollama.com/freehuntx/qwen3-coder/tags) |

When a tag is updated on Ollama, the **digest** (ID in `ollama list`) changes after you pull.

### Check local state

```bash
./scripts/install.sh --check
```

Shows installed digests and what's pinned in `config/models.env`:

```bash
grep -E 'DIGEST|UPGRADED_AT' config/models.env
ollama list
```

If `ollama pull` finds nothing new, it finishes in seconds and the digest stays the same.

---

## Recommended routine

### Weekly (2 min, no downloads)

```bash
./scripts/install.sh --check
```

Review **Tools** section for outdated Homebrew packages.

### Monthly (or when you see a new release)

```bash
# Models only — safe, idempotent (~seconds if already current)
./scripts/install.sh --upgrade-models
```

If Ollama or OpenCode also need updates:

```bash
./scripts/install.sh --upgrade
```

### After any upgrade

```bash
./scripts/install.sh --verify
opencode run -i "Use read tool on GOAL.md and quote line 1"
```

---

## Model upgrade details

### Primary: `qwen3-coder:30b`

Official Ollama library model. Used as OpenCode default.

```bash
ollama pull qwen3-coder:30b
```

### Fast: `qwen3-coder:14b`

Official library has **no** 14b coder tag. This setup pulls the community build and aliases it:

```bash
ollama pull freehuntx/qwen3-coder:14b
ollama cp freehuntx/qwen3-coder:14b qwen3-coder:14b
```

`./scripts/install.sh --upgrade-models` does both automatically.

### Optional: 64k variant

Only if you previously ran `CREATE_64K=1`:

```bash
CREATE_64K=1 ./scripts/install.sh --upgrade
```

Recreates `qwen3-coder-64k` Modelfile from the updated 30b base.

---

## Options

```bash
SKIP_MODELS=1 ./scripts/install.sh --upgrade    # tools only, skip ollama pull
SKIP_BREW=1 ./scripts/install.sh --upgrade      # models + config, skip brew
SKIP_FAST=1 ./scripts/install.sh --upgrade-models   # skip 14b pull
```

---

## Optional: monthly reminder (cron)

```bash
# Edit crontab
crontab -e
```

Add (runs check every Monday 9:00, logs to ~/local-agentic-upgrade.log):

```cron
0 9 * * 1 cd ~/work/local-agentic-llm-setup && ./scripts/install.sh --check >> ~/local-agentic-upgrade.log 2>&1
```

To auto-upgrade models monthly (1st of month, 3:00):

```cron
0 3 1 * * cd ~/work/local-agentic-llm-setup && ./scripts/install.sh --upgrade-models >> ~/local-agentic-upgrade.log 2>&1
```

Review the log before relying on unattended upgrades.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `pull model manifest: file does not exist` | Wrong tag — check monitor URLs above |
| Digest unchanged after pull | Already on latest build for that tag |
| OpenCode still slow | Model was re-downloaded — first inference reloads RAM (~1–2 min for 30b) |
| `llama-server binary not found` after Ollama upgrade | `./scripts/install.sh --repair` |
| Verify fails on fast model | `./scripts/install.sh --upgrade-models` |

---

## Related

- Initial setup: [SETUP.md](SETUP.md)
- Model pins: `config/models.env` (gitignored; example in `config/models.env.example`)
