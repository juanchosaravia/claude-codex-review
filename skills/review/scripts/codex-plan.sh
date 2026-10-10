#!/usr/bin/env bash
# Send a plan file to Codex CLI for a read-only critical review.
# Usage: codex-plan.sh --plan FILE [--model SLUG] [--effort LEVEL] [--cwd DIR] [--context FILE] [--out FILE]
#        codex-plan.sh --list-models
set -euo pipefail
. "$(dirname "$0")/lib.sh"

list_models() {
  # Prefer `codex debug models` (works on a fresh install); fall back to the local cache.
  local codex json="" cache="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
  if codex=$(find_codex 2>/dev/null); then json=$("$codex" debug models 2>/dev/null) || json=""; fi
  if [ -z "$json" ] && [ -f "$cache" ]; then json=$(cat "$cache"); fi
  if [ -z "$json" ]; then
    echo "ERROR: could not get the model list ('codex debug models' failed and $cache is missing)" >&2; exit 1
  fi
  printf '%s' "$json" | python3 -c '
import json, sys
try:
    models = json.load(sys.stdin).get("models", [])
except ValueError as e:
    sys.exit(f"ERROR: could not parse the model list: {e}")
listed = [m for m in models if m.get("visibility") == "list"]
if not listed:
    sys.exit("ERROR: the model list is empty")
for m in sorted(listed, key=lambda m: m.get("priority", 99)):
    efforts = ",".join(r["effort"] for r in m.get("supported_reasoning_levels", []))
    print("\t".join([m["slug"], m["display_name"], "[" + efforts + "]"]))
'
}

PLAN="" MODEL="" EFFORT="" CWD="$PWD" CONTEXT="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) need_value "$@"; PLAN="$2"; shift 2;;
    --model) need_value "$@"; MODEL="$2"; shift 2;;
    --effort) need_value "$@"; EFFORT="$2"; shift 2;;
    --cwd) need_value "$@"; CWD="$2"; shift 2;;
    --context) need_value "$@"; CONTEXT="$2"; shift 2;;
    --out) need_value "$@"; OUT="$2"; shift 2;;
    --list-models) list_models; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$PLAN" ] || { echo "ERROR: --plan FILE is required" >&2; exit 2; }
require_readable plan "$PLAN"
[ -z "$CONTEXT" ] || require_readable context "$CONTEXT"
CODEX=$(find_codex)
require_login "$CODEX"
setup_run_dir

{
  cat <<'P'
You are a senior engineer reviewing an implementation PLAN written by another AI agent (Claude Code).
The plan has NOT been executed yet. Your job is to find problems before any code is written.

You are in a read-only sandbox in the project's working directory. Inspect the codebase as much as
needed to verify the plan's assumptions (file paths, APIs, existing patterns, tests, build setup).
Do NOT modify any files.

Review for:
1. Correctness: wrong assumptions about the code, non-existent files/APIs, logic errors.
2. Completeness: missing steps, migrations, tests, config, edge cases, error handling, rollback.
3. Risk: breaking changes, security issues, data loss, performance, concurrency.
4. Ordering & dependencies between steps.
5. Simpler alternatives / over-engineering / scope creep.
6. Consistency with existing conventions in the codebase.

Output format (markdown):
## Verdict
One of: APPROVE | APPROVE WITH CHANGES | REVISE — plus a one-paragraph summary.
## Critical issues
Numbered. Each: what's wrong, evidence (file:line where possible), concrete fix.
## Suggestions
Lower-severity improvements, same format.
## Questions
Ambiguities the plan author should resolve.
Be specific and terse. Do not restate the plan. If something is fine, don't mention it.
P
  if [ -n "$CONTEXT" ]; then
    printf '\n<task_context>\n'; cat "$CONTEXT"; printf '\n</task_context>\n'
  fi
  printf '\n<plan>\n'; cat "$PLAN"; printf '\n</plan>\n'
} > "$PROMPT_FILE"

ARGS=(exec --sandbox read-only --skip-git-repo-check --ephemeral --color never -C "$CWD" -o "$OUT")
[ -n "$MODEL" ] && ARGS+=(-m "$MODEL")
[ -n "$EFFORT" ] && ARGS+=(-c "model_reasoning_effort=\"$EFFORT\"")
ARGS+=(-)

run_codex "$PROMPT_FILE" "${ARGS[@]}"
