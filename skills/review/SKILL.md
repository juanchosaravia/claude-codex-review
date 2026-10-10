---
name: review
description: Use when the user asks to have Codex / GPT / OpenAI review, critique, or second-opinion either a plan Claude produced (plan mode or a plan written in chat) or code changes (uncommitted work, a branch vs base, or a commit). Runs the Codex CLI read-only with a user-chosen model and reasoning effort and brings the review back.
argument-hint: "[plan|code] [model-slug] [effort] [plan-path | --base BRANCH | --commit SHA]"
---

# Codex Review

Get an independent review of a plan or code changes from an OpenAI model via the Codex CLI.
Scripts live in `scripts/` next to this file. Below, `<skill-dir>` means this skill's base directory, which is shown when the skill loads. Always call the scripts by absolute path (`<skill-dir>/scripts/...`) because the user's working directory is their project:
- `codex-plan.sh`: plan review (`--list-models` prints the available models)
- `codex-code.sh`: code review of git changes
- `codex-auth.sh`: `status` (path, version, login state), `path`, `login-cmd`

## 0. Check Codex is installed and logged in

Run `<skill-dir>/scripts/codex-auth.sh status` before anything else. The scripts look for Codex in this order: `$CODEX_BIN`, then `codex` on PATH (npm/brew installs), then the copy bundled with the ChatGPT/Codex desktop app.

- **Exit 0, `LOGGED_IN=yes`**: continue.
- **Exit 3, `LOGGED_IN=no`**: stop and ask the user to log in by typing the printed `LOGIN_CMD` with a `!` prefix, e.g. `! codex login`. That opens a browser for ChatGPT sign-in. Don't run the login yourself: it needs the user's browser. Alternatives to mention:
  - Headless / SSH: `! <LOGIN_CMD> --device-auth`
  - API key: `! printenv OPENAI_API_KEY | <LOGIN_CMD> --with-api-key`

  Always build these from the printed `LOGIN_CMD`. Don't assume a bare `codex`: it may not be on PATH, or `CODEX_BIN` may point somewhere else.

  Once the user has logged in, run `status` again and continue.
- **Exit 127, not found**: tell the user to install Codex (`npm i -g @openai/codex` or `brew install codex`) and then log in. If Codex is installed somewhere unusual, they can set `CODEX_BIN`.

## 1. Decide the mode

- **plan**: the user says "plan", or the most recent output in this conversation is a plan that hasn't been implemented yet.
- **code**: the user says "code", "changes", "diff", "branch", "commit", "PR", or the work has already been implemented.
- If it's still unclear, ask (this can be a third question in the AskUserQuestion call in step 3).

## 2. Gather the input

First create a private staging folder for the files you write. The plan and context can contain proprietary details, and `/tmp` is shared with other users on the machine:

```bash
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/claude-review.XXXXXX")   # mode 700; print it and reuse the path below
```

**Plan mode.** In priority order:
1. A file path passed in the arguments → use it.
2. A plan written earlier **in this conversation** (plan mode or a plain "create a plan" reply) → write the most recent full plan verbatim to `$STAGE/plan.md`. Don't summarize or improve it.
3. Otherwise the newest file in `~/.claude/plans/` (`ls -t ~/.claude/plans/*.md | head -1`). Confirm with the user that it's the right plan.

If no plan exists, say so and stop.

**Code mode.** Pick the target:
- `--uncommitted` (default): staged, unstaged and untracked changes.
- `--base <branch>`: the current branch compared with the base. Use this when the work is committed on a feature branch. Detect the base with `git symbolic-ref refs/remotes/origin/HEAD` or fall back to `main`/`master`.
- `--commit <sha>`: a single commit.

Check `git status` / `git diff --stat` first. If the chosen target has no changes, say so and stop. The directory must be a git repo.

**Both modes.** If this conversation has relevant background, write `$STAGE/context.md` containing the user's original request, the plan the code implements (in code mode), and any constraints or decisions. Codex can't see this conversation. If the user named a focus area (e.g. "security", "concurrency"), pass it as `--focus` (code mode only).

## 3. Pick the model and effort

If the arguments include a model slug and/or effort (`low|medium|high|xhigh|max|ultra`), use them and skip asking.

Otherwise run `<skill-dir>/scripts/codex-plan.sh --list-models` and ask with **one** AskUserQuestion call. If `--list-models` exits non-zero, don't make up model names. Ask only about effort, and run without `--model` so Codex uses the user's default model (say so).

The AskUserQuestion call:
- **Model**: four options. Use the first four listed models and label them with their display names (e.g. "GPT-6.1 Sol"). Put "(Recommended)" on the first one. The user can type any other slug via "Other".
- **Effort**: `high (Recommended)`, `xhigh`, `max`, `medium`. Only offer efforts the chosen models support; `gpt-5.5` stops at `xhigh`, and `ultra` is only available on some models.

## 4. Run the review

Run it with Bash `run_in_background: true`, because reviews can take several minutes:

```bash
# plan
<skill-dir>/scripts/codex-plan.sh --plan "$STAGE/plan.md" \
  [--context "$STAGE/context.md"] --model <slug> --effort <effort> --cwd "$PWD"

# code
<skill-dir>/scripts/codex-code.sh [--uncommitted | --base main | --commit <sha>] \
  [--focus "security"] [--context "$STAGE/context.md"] \
  --model <slug> --effort <effort> --cwd "$PWD"
```

The Codex sandbox is read-only, so Codex can inspect the repo but can't change anything. Tell the user the review is running and which model and effort it's using. The output includes `REVIEW_FILE=...` followed by the review.

Exit codes: `2` means bad arguments or a missing file (fix the problem and run again); `3` or a `LOGIN_REQUIRED:` line means the user needs to log in (see step 0; use the exact command printed); `1` means Codex itself failed (show the log tail; if it's an unsupported-model error, run `--list-models` and ask again).

Each run gets its own folder `$TMPDIR/codex-review.XXXXXX/` with `review.md` and `codex.log`. The prompt file, which contains the plan and context, is deleted when the script exits, even if Codex fails or the run is interrupted. When the review is done, delete the staging folder with `rm -rf "$STAGE"`.

## 5. Report back

1. Show the Codex review, with the verdict or summary first. Keep its findings and priorities (P0–P3) and don't soften them.
2. Then add **your assessment** of each finding. Check it against the actual code, and say whether you agree, partly agree, or disagree and why. Codex can be wrong. Use the superpowers:receiving-code-review rigor: no performative agreement.
3. Offer to make the accepted changes (revise the plan or fix the code). Don't change anything without asking.
