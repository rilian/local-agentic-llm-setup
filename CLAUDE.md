# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **local LLM + OpenCode installer** for Mac Apple Silicon (M4 Pro, 24 GB RAM). It is not application code — `.venv/` is dependencies only. The stack runs a Rapid-MLX inference server locally and configures OpenCode CLI to use it.

## Key commands

```bash
# Install / upgrade
./scripts/install.sh                        # Fresh install: deps, model, server, OpenCode config, verify
./scripts/install.sh --upgrade              # Repair/upgrade all components
./scripts/install.sh --upgrade --best-model # Same, plus auto-switch to top-ranked catalog model

# Rapid-MLX server (launchd-managed)
./scripts/mlx-serve.sh start|stop|restart|status|logs
```

Always use these scripts for install/server/loop operations. Do not hand-roll installs or server management commands.

## Architecture

```
opencode CLI  ──►  Rapid-MLX server :8080/v1  ──►  Qwen3.5-4B-OptiQ-4bit (Apple Silicon)
     │                    ▲
     │             launchd LaunchAgent
     │             ai.local.mlx-server
     │
~/.config/opencode/opencode.json  (written by install.sh, sourced from opencode.json.example)
config/models.env                 (auto-generated, tracks pinned model + digest + versions)
```

**Rapid-MLX server**: Rapid-MLX in Python venv at `.venv`, served on `http://127.0.0.1:8080/v1` (OpenAI-compatible). Logs at `/tmp/mlx-server.log` and `/tmp/mlx-server.err`. Max 16384 tokens, prefix caching on, auto tool-call parser.

**install.sh**: orchestrates the entire lifecycle — venv + Rapid-MLX deps, model download from HuggingFace, OpenCode JSON config merge, LaunchAgent plist generation and load, full verification (health check + tool-call smoke test with `README.md`), and HF cache cleanup.



**config/recommended-models.json**: ranked model catalog for the `mac_24gb` profile (12 GB RAM budget). Used by `--best-model` to auto-switch. Includes a watch list for unreleased models.

## Important files

| File | Notes |
|------|-------|
| `opencode.json.example` | Canonical config template — edit this, not the live config |
| `opencode.json` | Live config, gitignored — written by install.sh from the example |
| `config/models.env` | Gitignored runtime state (pinned model, digest, versions) |
| `config/recommended-models.json` | Model catalog — edit to add/rank models |

## OpenCode config

**Model settings** in `opencode.json.example`:
- **`max_tokens: 16384`** — response budget (4× headroom vs. 32768 context window)
- **`tool_call: true`** — enable function calling
- **`context_length: 32768`** — model's native context window

For inference tuning (temperature, sampling, etc.), use Rapid-MLX server flags in `scripts/mlx-serve.sh`.

**Observability**:
- Run with: `opencode --debug --verbose`
- Monitor server in parallel: `./scripts/mlx-serve.sh logs --follow`
- Logs show token counts, inference latency, memory, cache stats

## Tool use guidelines

- Use **read / glob / grep** with scoped paths — not `find` or `tree` from `.`
- Never bulk-read: `.venv/`, `.git/`, `~/.cache/huggingface/`, `opencode.json`, `config/models.env`
- Troubleshooting: model down → `mlx-serve.sh status`; stale config → `install.sh --upgrade`; token limit → check logs and `agent_config.logging`
- No `git commit`, `git push`, or `install.sh --upgrade` unless explicitly asked
