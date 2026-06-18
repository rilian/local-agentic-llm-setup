# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **local LLM + OpenCode installer** for Mac Apple Silicon (M4 Pro, 24 GB RAM). It is not application code — `.venv/` is dependencies only. The stack runs an MLX inference server locally and configures OpenCode CLI to use it.

## Key commands

```bash
# Install / upgrade
./scripts/install.sh                        # Fresh install: deps, model, server, OpenCode config, verify
./scripts/install.sh --upgrade              # Repair/upgrade all components
./scripts/install.sh --upgrade --best-model # Same, plus auto-switch to top-ranked catalog model

# MLX server (launchd-managed)
./scripts/mlx-serve.sh start|stop|restart|status|logs

# Long-running agent tasks
./scripts/loop.sh "task description"        # Loops opencode run --continue; stops on LOOP_COMPLETE
./scripts/loop.sh "task" --max 10           # Override iteration cap (default 25)
./scripts/loop.sh "task" --model <id>       # Override model for this run
```

Always use these scripts for install/server/loop operations. Do not hand-roll installs or server management commands.

## Architecture

```
opencode CLI  ──►  Rapid-MLX server :8080/v1  ──►  Qwen3-8B-4bit (Apple MLX)
     │                    ▲
     │             launchd LaunchAgent
     │             ai.local.mlx-server
     │
~/.config/opencode/opencode.json  (written by install.sh, sourced from opencode.json.example)
config/models.env                 (auto-generated, tracks pinned model + digest + versions)
```

**MLX server**: Rapid-MLX in Python venv at `.venv`, served on `http://127.0.0.1:8080/v1` (OpenAI-compatible). Logs at `/tmp/mlx-server.log` and `/tmp/mlx-server.err`. Max 8192 tokens, prefix caching on, auto tool-call parser.

**install.sh** (~900 lines): orchestrates the entire lifecycle — venv + deps, model download from HuggingFace, OpenCode JSON config merge, LaunchAgent plist generation and load, full verification (health check + tool-call smoke test with `README.md`), and HF cache cleanup.

**loop.sh**: drives `opencode run --continue` in a loop. Reads prompt template from `prompts/loop.md`. Exits when agent outputs `LOOP_COMPLETE` or `LOOP_BLOCKED`.

**config/recommended-models.json**: ranked model catalog for the `mac_24gb` profile (12 GB RAM budget). Used by `--best-model` to auto-switch. Includes a watch list for unreleased models.

## Important files

| File | Notes |
|------|-------|
| `opencode.json.example` | Canonical config template — edit this, not the live config |
| `opencode.json` | Live config, gitignored — written by install.sh from the example |
| `config/models.env` | Gitignored runtime state (pinned model, digest, versions) |
| `config/recommended-models.json` | Model catalog — edit to add/rank models |
| `prompts/loop.md` | Prompt template for loop.sh |

## Tool use guidelines

- Use **read / glob / grep** with scoped paths — not `find` or `tree` from `.`
- Never bulk-read: `.venv/`, `.git/`, `~/.cache/huggingface/`, `opencode.json`, `config/models.env`
- Troubleshooting: model down → `mlx-serve.sh status`; stale config → `install.sh --upgrade`
- No `git commit`, `git push`, or `install.sh --upgrade` unless explicitly asked
