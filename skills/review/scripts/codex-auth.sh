#!/usr/bin/env bash
# Codex CLI location and login status.
# Usage: codex-auth.sh [status|path|login-cmd]
set -euo pipefail
. "$(dirname "$0")/lib.sh"
CODEX=$(find_codex)
case "${1:-status}" in
  path) echo "$CODEX";;
  login-cmd) login_cmd "$CODEX";;
  status)
    echo "CODEX_BIN=$CODEX"
    "$CODEX" --version
    if "$CODEX" login status; then echo "LOGGED_IN=yes"
    else echo "LOGGED_IN=no"; echo "LOGIN_CMD=$(login_cmd "$CODEX")"; exit 3; fi;;
  *) echo "Usage: codex-auth.sh [status|path|login-cmd]" >&2; exit 2;;
esac
