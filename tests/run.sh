#!/usr/bin/env bash
# Offline tests for the review scripts, run against tests/fake-codex.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/../skills/review/scripts"
export CODEX_BIN="$HERE/fake-codex.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export TMPDIR="$T"
fail=0

check() { # name expected_exit actual_exit [output_regex output]
  local name=$1 want=$2 got=$3
  if [ "$want" != "$got" ]; then echo "FAIL $name: exit $got, want $want"; fail=1; return; fi
  if [ -n "${4:-}" ] && ! printf '%s' "${5:-}" | grep -qE "$4"; then echo "FAIL $name: output missing /$4/"; fail=1; return; fi
  echo "ok   $name"
}
run() { OUTPUT=$("$@" 2>&1); RC=$?; }

printf '1. do x\n' > "$T/plan.md"
git init -q "$T/repo" && echo a > "$T/repo/f" && git -C "$T/repo" add . \
  && git -C "$T/repo" -c user.email=t@t -c user.name=t commit -qm i && echo b >> "$T/repo/f"

run "$S/codex-plan.sh" --list-models;                     check "list-models shows listed model" 0 $RC 'fake-1' "$OUTPUT"
printf '%s' "$OUTPUT" | grep -q hidden && { echo "FAIL list-models shows hidden model"; fail=1; }
run "$S/codex-auth.sh" status;                            check "auth status logged in" 0 $RC 'LOGGED_IN=yes' "$OUTPUT"
FAKE_LOGGED_OUT=1 run "$S/codex-auth.sh" status;          check "auth status logged out" 3 $RC 'LOGGED_IN=no' "$OUTPUT"
FAKE_LOGGED_OUT=1 run "$S/codex-plan.sh" --plan "$T/plan.md"; check "plan requires login" 3 $RC 'LOGIN_REQUIRED' "$OUTPUT"
CODEX_BIN=/nonexistent run "$S/codex-auth.sh" status;     check "codex not found" 127 $RC

run "$S/codex-plan.sh" --plan;                            check "plan: option missing value" 2 $RC 'requires a value' "$OUTPUT"
run "$S/codex-code.sh" --base;                            check "code: option missing value" 2 $RC 'requires a value' "$OUTPUT"
run "$S/codex-code.sh" --base --model x;                  check "code: value is another flag" 2 $RC 'requires a value' "$OUTPUT"
run "$S/codex-plan.sh" --plan "$T/nope.md";               check "plan: missing plan file" 2 $RC
run "$S/codex-plan.sh" --plan "$T/plan.md" --context "$T/nope.md"; check "plan: missing context file" 2 $RC
run "$S/codex-code.sh" --cwd "$T" ;                       check "code: not a git repo" 2 $RC 'not a git repository' "$OUTPUT"
run "$S/codex-code.sh" --cwd "$T/repo" --context "$T/nope.md"; check "code: missing context file" 2 $RC

run "$S/codex-plan.sh" --plan "$T/plan.md" --model fake-1 --effort low; check "plan review succeeds" 0 $RC 'FAKE REVIEW' "$OUTPUT"
dir=$(dirname "$(printf '%s\n' "$OUTPUT" | sed -n 's/^REVIEW_FILE=//p')")
[ -f "$dir/review.md" ] && [ ! -e "$dir/prompt.md" ] && echo "ok   plan: prompt file removed, review kept" || { echo "FAIL plan: prompt.md left behind in $dir"; fail=1; }
run "$S/codex-code.sh" --cwd "$T/repo";                   check "code review (uncommitted)" 0 $RC 'FAKE REVIEW' "$OUTPUT"
run "$S/codex-code.sh" --cwd "$T/repo" --focus security --context "$T/plan.md"; check "code review (focus+context)" 0 $RC 'FAKE REVIEW' "$OUTPUT"

[ $fail -eq 0 ] && echo "ALL PASSED" || { echo "FAILURES"; exit 1; }
