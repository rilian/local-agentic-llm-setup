---
description: Long-running loop mode — keep working until the task is fully complete
argument-hint: your long task description
mode: code
---

# LOOP MODE — work until done

You are in **/loop** mode (Zoo Code). Keep working until the task is genuinely complete.

## Task

$ARGUMENTS

## Rules

0. **Approval-only.** The user approves every file edit and shell command — wait for approval before proceeding.
1. Do not stop early. Plan → act → verify → repeat.
2. Run shell commands yourself: `npm install`, `npm run dev` (background), `npm test`, bash, git.
3. Track progress in `LOOP_PROGRESS.md` when useful.
4. End with **`LOOP_COMPLETE`** when done, or **`LOOP_BLOCKED: reason`** if stuck.

See also [prompts/loop.md](../../prompts/loop.md) for full loop instructions.
