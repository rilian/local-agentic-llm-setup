# Upgrading — MLX stack

---

## Quick upgrade (recommended)

```bash
./scripts/install.sh --upgrade
```

This upgrades:

- OpenCode (via Homebrew or `opencode upgrade`)
- Python deps in `.venv` (`mlx`, `mlx-lm`)
- Re-downloads model weights (unless `SKIP_MODELS=1`)
- Restarts MLX server and re-applies OpenCode config

---

## Check before upgrading

```bash
./scripts/install.sh --check
```

Shows mlx-lm version, OpenCode version, pinned model digest.

---

## Upgrade model weights only

```bash
./scripts/install.sh --upgrade-models
```

Re-downloads `mlx-community/Qwen3.5-9B-OptiQ-4bit` from HuggingFace and restarts the server.

---

## Upgrade OpenCode only

```bash
brew upgrade anomalyco/tap/opencode
# or
opencode upgrade
```

Then re-apply config:

```bash
./scripts/install.sh --repair
```

---

## Upgrade mlx-lm only

```bash
.venv/bin/pip install -U mlx mlx-lm
./scripts/mlx-serve.sh restart
./scripts/install.sh --verify
```

---

## Free disk space

Remove unused HuggingFace model caches (keeps current `PRIMARY_MODEL`):

```bash
./scripts/install.sh --cleanup
```

---

## Troubleshooting after upgrade

| Symptom | Fix |
|---------|-----|
| API down | `./scripts/mlx-serve.sh restart` |
| OpenCode wrong provider | `./scripts/install.sh --repair` |
| Slow after upgrade | First prompt reloads model — wait ~60s |
| pip errors | `rm -rf .venv && ./scripts/install.sh` |

---

## Pin versions

`config/models.env` records:

- `PRIMARY_MODEL`
- `PRIMARY_DIGEST` (HuggingFace revision)
- `MLX_LM_VERSION`
- `OPENCODE_VERSION`
- `UPGRADED_AT`

Commit `config/models.env.example` changes; keep `config/models.env` local (gitignored).
