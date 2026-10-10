# Shared helpers for codex-review scripts. Source, don't execute.

# Resolve the Codex CLI: $CODEX_BIN, then PATH (npm/brew installs), then app-bundled copies.
find_codex() {
  if [ -n "${CODEX_BIN:-}" ]; then
    [ -x "$CODEX_BIN" ] && { echo "$CODEX_BIN"; return 0; }
    echo "ERROR: CODEX_BIN=$CODEX_BIN is not executable" >&2; return 127
  fi
  if command -v codex >/dev/null 2>&1; then command -v codex; return 0; fi
  local c
  for c in /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex \
           /Applications/Codex.app/Contents/Resources/codex-cli/bin/codex \
           "$HOME/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex" \
           /opt/homebrew/bin/codex /usr/local/bin/codex "$HOME/.local/bin/codex"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  echo "ERROR: Codex CLI not found. Install it with 'npm i -g @openai/codex' or 'brew install codex', or set CODEX_BIN." >&2
  return 127
}

# Command the user should type to log in (bare 'codex' if it's on PATH, else the absolute path).
login_cmd() {
  if command -v codex >/dev/null 2>&1 && [ "$(command -v codex)" = "$1" ]; then echo "codex login"
  else printf '%q login\n' "$1"; fi
}

# Fail with exit 2 if option $1 has no value (missing, empty, or another --flag).
need_value() {
  if [ $# -lt 2 ] || [ -z "$2" ]; then echo "ERROR: $1 requires a value" >&2; exit 2; fi
  case "$2" in --*) echo "ERROR: $1 requires a value (got '$2')" >&2; exit 2;; esac
}

# Exit 3 with instructions if not logged in.
require_login() {
  local codex="$1" status
  if ! status=$("$codex" login status 2>&1); then
    echo "ERROR: Codex is not logged in ($status)." >&2
    echo "LOGIN_REQUIRED: ask the user to run:  ! $(login_cmd "$codex")" >&2
    echo "  (headless/SSH: add --device-auth; API key: printenv OPENAI_API_KEY | $(login_cmd "$codex") --with-api-key)" >&2
    exit 3
  fi
}

# Read a file the user explicitly passed, or fail loudly.
require_readable() {
  [ -f "$2" ] && [ -r "$2" ] || { echo "ERROR: $1 file '$2' does not exist or is not readable" >&2; exit 2; }
}

# Run codex with stdin from $1, writing the log next to the review; fail with the log tail.
run_codex() {
  local stdin="$1"; shift
  echo "Running: $CODEX $* (model=${MODEL:-config default}, effort=${EFFORT:-config default})" >&2
  if ! "$CODEX" "$@" < "$stdin" > "$LOG" 2>&1; then
    echo "ERROR: codex exited non-zero. Log: $LOG" >&2; tail -30 "$LOG" >&2
    if grep -qiE 'not logged in|unauthori[sz]ed|"status": *401|token (has )?expired|please (re-?)?log ?in' "$LOG"; then
      echo "LOGIN_REQUIRED: ask the user to run:  ! $(login_cmd "$CODEX")" >&2
    fi
    exit 1
  fi
  [ -s "$OUT" ] || { echo "ERROR: codex finished but wrote no review. Log: $LOG" >&2; exit 1; }
  echo "REVIEW_FILE=$OUT"
  cat "$OUT"
}

# Per-run directory holding the review and log (kept), plus a scratch prompt file removed on exit.
setup_run_dir() {
  RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-review.XXXXXX")
  OUT=${OUT:-$RUN_DIR/review.md}
  LOG=$RUN_DIR/codex.log
  PROMPT_FILE=$RUN_DIR/prompt.md
  trap 'rm -f "$PROMPT_FILE"' EXIT
  trap 'exit 130' INT TERM
}
