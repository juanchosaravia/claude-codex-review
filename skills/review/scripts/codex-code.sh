#!/usr/bin/env bash
# Run a Codex code review on git changes (read-only).
# Usage: codex-code.sh [--uncommitted | --base BRANCH | --commit SHA] [--model SLUG] [--effort LEVEL]
#                      [--cwd DIR] [--focus TEXT] [--context FILE] [--out FILE]
# Codex can't combine a target flag with custom instructions, so when --focus/--context is given
# the target is described in the prompt instead.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

TARGET="--uncommitted" TARGET_VAL="" MODEL="" EFFORT="" CWD="$PWD" FOCUS="" CONTEXT="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --uncommitted) TARGET="--uncommitted"; TARGET_VAL=""; shift;;
    --base) TARGET="--base"; TARGET_VAL="$2"; shift 2;;
    --commit) TARGET="--commit"; TARGET_VAL="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --effort) EFFORT="$2"; shift 2;;
    --cwd) CWD="$2"; shift 2;;
    --focus) FOCUS="$2"; shift 2;;
    --context) CONTEXT="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: $CWD is not a git repository" >&2; exit 2; }
[ -z "$CONTEXT" ] || require_readable context "$CONTEXT"
CODEX=$(find_codex)
require_login "$CODEX"
setup_run_dir

ARGS=(exec --sandbox read-only --color never -C "$CWD" review --ephemeral -o "$OUT")
[ -n "$MODEL" ] && ARGS+=(-m "$MODEL")
[ -n "$EFFORT" ] && ARGS+=(-c "model_reasoning_effort=\"$EFFORT\"")

if [ -z "$FOCUS" ] && [ -z "$CONTEXT" ]; then
  ARGS+=("$TARGET"); [ -n "$TARGET_VAL" ] && ARGS+=("$TARGET_VAL")
  STDIN=/dev/null
else
  case "$TARGET" in
    --uncommitted) SCOPE="the uncommitted changes: staged, unstaged and untracked files (git status, git diff HEAD, and read untracked files)";;
    --base) SCOPE="the changes on the current branch against base branch '$TARGET_VAL' (git diff $TARGET_VAL...HEAD, plus any uncommitted changes)";;
    --commit) SCOPE="the changes introduced by commit $TARGET_VAL (git show $TARGET_VAL)";;
  esac
  {
    echo "Review $SCOPE. Report only real problems: bugs, regressions, security issues, missing edge cases, and deviations from the intended task. Give each a priority and a file:line."
    [ -n "$FOCUS" ] && printf '\nFocus especially on: %s\n' "$FOCUS"
    if [ -n "$CONTEXT" ]; then
      printf '\n<task_context>\n'; cat "$CONTEXT"; printf '\n</task_context>\n'
    fi
  } > "$PROMPT_FILE"
  STDIN=$PROMPT_FILE
  ARGS+=(-)
fi

run_codex "$STDIN" "${ARGS[@]}"
