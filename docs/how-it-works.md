# How it works

The installed `~/bin/mkproj` launcher delegates to `bootstrap.sh`.
`lib/input.sh` validates bounded arguments and prompts; `lib/runtime.sh` implements
backups, Git preflight, private-path guard installation, and read-only diagnostics.

## Setup flow

Setup validates the target and confirms the plan before mutation, then obtains
project and bare-destination locks. It creates Git/venv/scaffold files, installs
native private-path guards, verifies configuration/privacy/venv, installs project
dependencies, optionally configures globals, and commits only generated files.
Verification precedes commit/push. Finally it releases locks and launches the
selected agent, or exits for `--agent=none`.

## Templates

Templates live under `templates/<name>/` with three subtrees:

- `project/` -- files copied to the project root
- `claude/` -- files copied to `.claude/` (hooks, rules, skills)
- `git-hooks/` -- files copied to `.githooks/`

The default template is set in `templates/.default`. The tree-walkers
`install_project_tree()` and `install_claude_tree()` scan those subtrees and
copy each file to its destination, applying `{{PROJECT_NAME}}` and `{{MODULE_NAME}}`
macro substitution in both file content and path segments. `.gitkeep` files cause
the parent directory to be created but are not themselves copied.

Global files not tied to any specific template (such as `keybindings.json`) live
in `templates/global/`.

`.claude/hooks` are Claude Code agent hooks; `.githooks` are native Git guards.
They are different and are installed by separate phases.

## Skills

Every new project receives the skills bundled in `templates/<name>/claude/skills/`.
Skills are Markdown files in `.claude/skills/` that Claude Code loads when
invoked as `/skillname`. The `claude-code` template ships two:

- `/audit` -- proactive project improvement review; run it once you have a working draft
- `/scan` -- privacy and secrets scan; checks for personal identifiers, absolute paths, API key patterns, and mismatched gitignore entries

## Bootstrap phases

| Phase | What it does |
|-------|-------------|
| 1 Preflight | validates name, path, Git state, prereqs |
| 2 Git | `git init`, bare repo creation, remote config |
| 3 Python | creates `.venv`, copies `requirements.txt` |
| 4 Root files | (stub in v3; handled by tree-walker) |
| 5 Claude config | `install_claude_tree()` copies hooks/rules/skills; writes `settings.json` |
| 6 Project structure | `install_project_tree()` copies project files; creates `src/<module>/`; installs Git guards |
| 7 Global setup | optional shell config, keybindings, global hook registration |
| 8 Registry | writes `.mkproj` with file hashes |
| 9 Verify | checks all required paths exist and are correct |

## Test mode

`--test` creates its entire scaffold and bare repo beneath one temporary root,
isolates Git identity/configuration, skips pushes and global changes, and cleans
up using an EXIT trap. Errors report the failing phase and return nonzero.

`install.sh --check` inspects prerequisites without installation. Normal installation
backs up replaced launchers and tests a candidate before publishing it.
See reliability.md for invariants and recovery details.
