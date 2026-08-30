# CLAUDE.md

This is how I create claude code projects, with all the bells and whistles AUTOMATICALLY. Everything is configurable.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Response format (required on every response)

**First character:** Begin every response with a single ✓ character followed by a newline, then the response body. This is a health indicator -- when the user stops seeing ✓, Claude Code has lost its instruction context.

**Second line:** Immediately after the ✓, read `responses/.last-saved` and report the actual filename saved by the previous Stop hook:

```
✓
Last saved: responses/20260828-214500.txt
```

If `responses/.last-saved` does not exist or is empty, write `Last saved: (none yet)`.

This is real confirmation -- the file is written by `save-response.sh` after each exchange and contains the human-readable query and response (not tool output):

```
=== QUERY ===
<user message>

=== RESPONSE ===
<Claude response>
```

**Git commits:** At the end of any response where files were added, changed, or deleted, commit explicitly:

```bash
git add <specific changed files>
git commit -m "descriptive message stating what changed and why"
git push origin main
```

The `auto-commit.sh` Stop hook is a safety net only -- Claude commits first with a meaningful message.

## Behaviour directives

**Proactive:** When asking a question or presenting options, always include a recommendation with brief reasoning. Do not wait for the user to ask which option is better -- state it. The user is not the expert; Claude is.

**Suggestions:** If a better approach exists for any task, mention it in one line before proceeding. Do not implement it without a yes.

## Purpose

This repo provides `bootstrap.sh` -- a bash script that scaffolds a complete Claude Code Python project from an empty directory. Run via `mkproj` (a thin launcher in `~/bin/`). All logic lives here so changes are version-controlled and take effect immediately on the next `mkproj` run.

## Commands

```bash
# Install ~/bin/mkproj (one-time, after cloning)
bash install.sh

# Test the bootstrap end-to-end (from inside Claude Code)
mkproj --test

# Bootstrap a new project
cd ~/Projects && mkproj myproject
```

## Architecture

```
bootstrap.sh          ← all logic; 9 sequential phases
install.sh            ← creates ~/bin/proj (thin launcher, never changes)
templates/            ← files copied verbatim (or with {{PROJECT_NAME}} substitution) into new projects
  hooks/              ← save-response.sh, auto-commit.sh, auto-import-skill.sh (maintained here)
  docs/               ← 8 stub doc files for new projects
  tasks/              ← todo.md, skills-manifest.md stubs
  CLAUDE.md           ← the CLAUDE.md that new projects receive
  .gitignore / .gitattributes / .env.example / run.sh / test.sh / requirements.txt / README.md
docs/                 ← documentation for project-bootstrap itself
projSetup.md          ← original spec (reference only)
```

## Key design rules

- `bootstrap.sh` is **idempotent**: every file/dir creation is guarded by an existence check. Re-running after a failed run is safe.
- It **stops hard** if the target project has more than 1 commit, or has 1 commit that is not "Initial project scaffold". Running bootstrap on a live project is always a mistake.
- The bare repo collision (existing `~/Repositories/<name>.git`) surfaces a `[d/o/q]` prompt. `q`/Enter is the safe default.
- `~/bin/proj` calls `exec bootstrap.sh` -- one hop, no indirection.
- The 8 dotclaude marketplace hooks are copied by glob from `~/.claude/plugins/marketplaces/dotclaude/hooks/*.sh`. New marketplace hooks are picked up automatically.
- `save-response.sh`, `auto-commit.sh`, and `auto-import-skill.sh` are bundled in `templates/hooks/` (not from the marketplace).
- `generate_settings_json()` uses `<<'EOF'` so `$CLAUDE_PROJECT_DIR` is written literally into the JSON for Claude Code to expand at runtime.

## Modifying

- To change what a new project looks like: edit files in `templates/`.
- To change bootstrap behaviour: edit `bootstrap.sh` phase functions.
- To add a new phase: add a `phaseN_name()` function and call it in `main()`.
- After any change here, the next `proj` run picks it up automatically.
