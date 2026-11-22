# Overview

## 1. What it is

`project-bootstrap` is a single command that turns an empty folder into a fully configured Claude Code development environment in under a minute. It is designed for developers who work via SSH and build Python projects with Claude Code as the primary coding assistant.

## 2. What you get

Running `mkproj myproject` produces:

- A local git repo with optional bare-repo backup and GitHub remote
- A Python virtual environment (`.venv`)
- Claude Code hooks wired and ready: safety guards, auto-save, auto-commit, session start
- A `settings.json` controlling what Claude Code is and is not allowed to do
- Claude skills installed in `.claude/skills/` and ready to invoke as `/audit` and `/scan`
- Standard project scaffolding: `docs/`, `tasks/`, `responses/`, `run.sh`, `test.sh`
- A `CLAUDE.md` with standing instructions Claude reads at the start of every session
- A named `screen` session so the terminal survives SSH disconnects

## 3. Non-obvious capabilities

These behaviors go beyond "copy some files":

**Safety guards that run at the Git level, not just inside the agent.** Two native Git hooks (`.githooks/pre-commit` and `.githooks/pre-push`) enforce privacy rules before any commit or push reaches the index. They check both explicit path patterns (`responses/`, `*.pem`, `.env.*`, etc.) and git's own ignore rules, so private files cannot slip through even if Claude Code is bypassed.

**Idempotency.** Every file and directory creation is guarded by an existence check. Re-running `mkproj` on a partially bootstrapped project is safe -- it fills in what's missing and skips what's already there. Bootstrap refuses to run on any project with more than one commit, so running it on a live project is impossible.

**Update tracking with conflict resolution.** Every bootstrapped project carries a `.mkproj` registry that records the template hash and the installed hash for each file. `mkproj update` and `mkproj scan` use those hashes to determine whether a file has drifted from the template. Files you've edited are preserved; files the template changed are updated silently; files where both sides changed get a conflict prompt: update / keep / defer / stop. This is a real update system, not a blind overwrite.

**File tiers.** Template files are classified as `directive`, `infrastructure`, or `optional`. `update --safe` only touches infrastructure-tier auto-updates, never directive files. `restore` reinstates infrastructure files that have been deleted or corrupted. `check` and `report` audit the tier state without making changes.

**Staged-only auto-commit.** The Stop hook only commits files that were explicitly staged by Claude during the session. It does not sweep up unrelated untracked or modified files, so your working tree is never touched by an automatic commit.

**Screen session management.** Bootstrap launches the agent inside a named `screen` session. If the SSH connection drops, the session persists. Claude Code resumes where it left off.

**Locked concurrent access.** Bootstrap obtains flock-based locks on the project directory and the bare repository destination before making any changes. Two concurrent `mkproj` runs on the same target cannot corrupt each other.

**Verified backups before any configuration replacement.** Before overwriting any existing configuration file (global settings, keybindings, hooks), bootstrap copies it to a timestamped backup in `backups/` and verifies the copy with `cmp` before proceeding. The replacement uses a temp file and atomic rename.

**Non-interactive mode.** Pass `--agent=claude --no-global` and pipe three newlines to skip all prompts. This works in CI, scripts, or remote provisioning without any user interaction.

## 4. What it does not do

- Install Python packages -- you fill in `requirements.txt` first
- Write any application code
- Make any content-specific decisions -- everything is generic scaffolding
- Set up git remotes automatically -- that is a separate, optional step (see [adding-remotes.md](adding-remotes.md))

## 5. How it is maintained

`project-bootstrap` lives at `~/Projects/project-bootstrap`. To change what new projects look like, edit files in `templates/claude-code/`. The `mkproj` command always executes the current version of `bootstrap.sh`, so changes take effect immediately.

## 6. Reading order

| Doc | Audience |
|-----|----------|
| This file | Anyone evaluating the tool |
| [install.md](install.md) | First-time setup on a new machine |
| [usage.md](usage.md) | Day-to-day use |
| [adding-remotes.md](adding-remotes.md) | Setting up git remotes (local bare repo, GitHub, etc.) |
| [how-it-works.md](how-it-works.md) | Understanding internals, debugging |
| [customizing.md](customizing.md) | Changing templates or adding phases |
| [troubleshooting.md](troubleshooting.md) | When something goes wrong |
| [doc-index.md](doc-index.md) | Alphabetical index of all topics |
