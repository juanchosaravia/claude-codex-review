# claude-codex-review

[![CI](https://github.com/juanchosaravia/claude-codex-review/actions/workflows/ci.yml/badge.svg)](https://github.com/juanchosaravia/claude-codex-review/actions/workflows/ci.yml)

Get a second opinion from **OpenAI Codex** on what **Claude Code** produces, without leaving Claude Code.

- **Plan review**: Codex critiques a plan before any code is written. This works with plan mode and with plans Claude writes as a normal chat reply.
- **Code review**: Codex reviews your uncommitted changes, a branch compared with its base, or a single commit.
- **Your choice of model**: pick the GPT model and reasoning effort each time, or pass them inline.
- **Read-only**: Codex runs in a read-only sandbox. It can read your repo to check its claims, but it can't change anything.
- **Claude checks the findings**: Claude reports Codex's verdict, then checks each finding against the code and says whether it agrees. It only makes changes if you ask.

## Install

In Claude Code:

```
/plugin marketplace add juanchosaravia/claude-codex-review
/plugin install codex-review@claude-codex-review
```

Restart Claude Code (or start a new session) to load the skill.

### Requirements

- The [Codex CLI](https://github.com/openai/codex), logged in:
  ```bash
  npm i -g @openai/codex   # or: brew install codex
  codex login              # sign in with ChatGPT (or --device-auth / --with-api-key)
  ```
  The ChatGPT desktop app on macOS includes the Codex CLI. If you use that copy, it's detected automatically even though it isn't on your `PATH`.
- `bash`, `git`, `python3`. These come with macOS and most Linux distributions.

If you aren't logged in, the skill stops and tells you the exact login command to run. You can run it from inside Claude Code with a `!` prefix, e.g. `! codex login`.

## Usage

```
/codex-review:review plan                          # review the plan Claude just wrote
/codex-review:review code                          # review uncommitted changes
/codex-review:review code --base main              # review the whole branch against main
/codex-review:review code --commit abc123          # review one commit
/codex-review:review code gpt-6.1-sol xhigh        # skip the model and effort questions
/codex-review:review plan docs/plan.md             # review a plan file
```

Or just ask: *"have Codex review this plan"*, *"get a second opinion from GPT on my changes, focus on security"*.

If you don't specify a model and effort, Claude asks you to choose. The model list comes from your local Codex model cache, so it always matches what your account can use.

## How it works

| Script | What it does |
| --- | --- |
| `codex-auth.sh` | Finds the Codex CLI and checks `codex login status` |
| `codex-plan.sh` | Sends the plan plus context to `codex exec --sandbox read-only` with a structured review prompt (verdict, critical issues, suggestions, questions) |
| `codex-code.sh` | Runs `codex exec review` on `--uncommitted`, `--base <branch>` or `--commit <sha>` |

Codex can't see your Claude conversation. So Claude writes a short context file with your original request, the plan the code implements, and any constraints. The review checks the work against what you asked for, not just for generic bugs.

Codex is found in this order: `$CODEX_BIN`, then `codex` on `PATH`, then the copy bundled with the ChatGPT/Codex desktop app.

Each review is saved in `$TMPDIR/codex-review.XXXXXX/` as `review.md` and `codex.log`. The temp prompt file is deleted when the script exits.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Review completed |
| 1 | Codex failed (see `codex.log`; e.g. an unsupported model) |
| 2 | Bad arguments, a missing plan or context file, or not a git repo |
| 3 | Codex isn't logged in |
| 127 | Codex CLI not found |

## Development

The tests run the scripts against a fake `codex` (`tests/fake-codex.sh`), so they need no login or network:

```bash
bash tests/run.sh
```

CI runs them on Linux and macOS (bash 3.2), plus ShellCheck and `claude plugin validate --strict`.

## License

MIT
