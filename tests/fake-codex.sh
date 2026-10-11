#!/usr/bin/env bash
# Minimal stand-in for the Codex CLI, used by tests/run.sh via CODEX_BIN.
case "${1:-} ${2:-}" in
  "login status")
    if [ -n "${FAKE_LOGGED_OUT:-}" ]; then echo "Not logged in"; exit 1; fi
    echo "Logged in using FakeAccount"; exit 0;;
  "debug models")
    echo '{"models":[{"slug":"fake-1","display_name":"Fake-1","visibility":"list","priority":1,"supported_reasoning_levels":[{"effort":"low"},{"effort":"high"}]},{"slug":"hidden","display_name":"Hidden","visibility":"hide","priority":2}]}'
    exit 0;;
esac
[ "${1:-}" = "--version" ] && { echo "fake-codex 0.0.0"; exit 0; }
# exec / exec review: write a canned review to the -o file.
out=""
while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
[ -n "$out" ] && echo "FAKE REVIEW" > "$out"
exit 0
