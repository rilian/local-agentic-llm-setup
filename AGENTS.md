# Agent instructions

This repo is a **local LLM + OpenCode installer** (`scripts/`, `config/`, `README.md`) — not application code. `.venv/` is dependencies only.

## Before using tools

- General or external-topic questions: answer directly; do not search this repo.
- Use **read / glob / grep** with scoped paths — not bash `find`, `tree`, or recursive scans from `.`
- Never bulk-read: `.venv/`, `node_modules/`, `.git/`, `~/.cache/huggingface/`, or secret config (`opencode.json`, `config/models.env`, `.env*`)
- If a tool is denied, continue with another approach — do not stop.

## Working here

- Keep output small; local context fills fast. One focused change per turn.
- Use repo scripts: `install.sh`, `mlx-serve.sh`, `loop.sh` — don't hand-roll installs or server commands.
- Read before editing; minimal diffs. No commit/push/upgrade/destructive commands unless asked.
- Troubleshooting: model down → `mlx-serve.sh status`; OOM → avoid bulk scans; stale config → `install.sh --upgrade`.
