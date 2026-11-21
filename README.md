# project-bootstrap

mkproj scaffolds Linux Python projects with Git, a project `.venv`, Claude Code
hooks, shared CLAUDE.md instructions, and an AGENTS.md pointer for Codex.

    mkproj my_tool    # run from a parent directory -- creates the folder
    mkproj            # run from inside an empty directory -- adopts the folder name

A lot more is possible. Some of what's available:

## Commands

**Create a project**

    mkproj my_tool                         # create project in a new folder
    mkproj                                 # adopt current directory name as project name
    mkproj --agent=claude my_tool          # scaffold and launch Claude Code (default)
    mkproj --agent=codex my_tool           # scaffold and launch Codex
    mkproj --agent=none my_tool            # scaffold only, no agent launch
    mkproj --no-global my_tool             # skip global shell/hook configuration
    mkproj --keybindings my_tool           # install managed terminal keybindings
    mkproj --template claude-code my_tool  # use a specific named template
    mkproj --dry-run my_tool               # show what would happen, touch nothing

**Templates**

    mkproj --list-templates                # print available templates and exit

**Diagnostics**

    mkproj --help
    mkproj --version
    mkproj --doctor                        # check prerequisites and project health
    mkproj --test                          # run full isolated scaffold test (no side effects)

**Update a project**

    mkproj --update                        # update current project from latest template
    mkproj --safe-update                   # update only optional files, skip directives/infra
    mkproj --force-file PATH               # force-update a single file, bypassing conflict skip

**Manage multiple projects**

    mkproj --scan ~/Projects               # update all mkproj projects under a directory
    mkproj --status ~/Projects             # dry-run scan: show what would change, touch nothing
    mkproj --pending ~/Projects            # interactively resolve all deferred conflicts

**Enroll an existing project**

    mkproj --adopt                         # enroll an existing Claude Code project in mkproj

**File tier audit**

    mkproj --check ~/Projects              # audit tier compliance, exit 1 if issues found
    mkproj --report ~/Projects             # print tier report, touch nothing
    mkproj --list-tiers                    # show each tracked file and its tier
    mkproj --restore-infra                 # reinstate deleted or corrupted infrastructure files

**Conflict resolution**

    mkproj --accept --file PATH            # accept the template version of a conflicted file

Names: 1-64 lowercase letters/digits/underscores/hyphens, starting with a letter.
No trailing or consecutive hyphens. No Python keywords. When adopting a directory,
the folder name is validated by the same rules.

---

## Two ways to run it

    # From a parent directory -- mkproj creates the folder
    cd ~/Projects && mkproj my_tool

    # From inside an existing empty directory -- folder name is adopted
    mkdir ~/Projects/my_tool && cd ~/Projects/my_tool && mkproj

Bootstrap refuses real project commits, dirty tracked files, staged changes,
nested repositories, detached HEAD, conflicting origins, and unrelated
bare-repository destinations.

## What goes beyond "copy files and make folders"

**Safety guards at the Git level.** Two native Git hooks (`.githooks/pre-commit` and `.githooks/pre-push`) enforce privacy rules before any commit or push reaches the index. They check both explicit path patterns (`responses/`, `*.pem`, `.env.*`, etc.) and git's own ignore rules -- so private files cannot slip through even if the agent is bypassed.

**Update tracking with conflict resolution.** Every bootstrapped project carries a `.mkproj` registry of template vs. installed hashes per file. `mkproj --update` uses those hashes to update what changed in the template, preserve what you've edited, and prompt on genuine conflicts (update / keep / defer / stop). `mkproj --scan ~/Projects` runs this across every project under a directory at once.

**File tiers.** Template files are classified as `directive`, `infrastructure`, or `optional`. `--safe-update` only touches `optional` files. `--restore-infra` reinstates infrastructure files that were deleted or corrupted. `--check` and `--report` audit tier state without changing anything.

**Staged-only auto-commit.** The Stop hook commits only files Claude explicitly staged during the session. It never sweeps unrelated files from the working tree.

**Locked concurrent access.** Bootstrap holds flock-based locks on the project and bare-repo destination. Two concurrent `mkproj` runs on the same target cannot corrupt each other.

**Verified backups before any config replacement.** Every configuration overwrite is preceded by a `cp --preserve=all` to a timestamped backup in `backups/`, verified with `cmp`, before the atomic replacement happens.

**Skills in every project.** New projects receive `/audit` (proactive improvement review) and `/scan` (privacy and secrets check) as Claude Code skills ready to invoke on day one.

**Non-interactive mode.** `--agent=claude --no-global` plus three piped newlines skips all prompts -- usable in CI or remote provisioning.

## Linux workflow

Setup offers a local bare origin, Claude/Codex/no launch, and optional global
shell/hook setup (default No). Existing status settings are preserved.
Verified filesystem backups precede configuration replacement. The installer
backs up an existing mkproj launcher and retains the legacy proj command.

Only files generated by the current run are staged. Verification and dependency
installation through the project `.venv` precede the scaffold commit and push.
Native pre-commit/pre-push guards reject private paths. The Stop auto-commit hook
only commits files already staged explicitly and surfaces failures.

`responses/` is entirely private, with no tracked placeholder. Venvs, secrets,
local agent state, keys, logs, and timestamped backups are excluded from Git.
Ignore rules do not remove private data from old history; Git hooks can also be
bypassed deliberately. See docs/reliability.md for the exact scope.

## Templates

Templates live under `templates/<name>/project/`, `templates/<name>/claude/`, and
`templates/<name>/git-hooks/`. The default is `claude-code`. To add a new template,
create a directory following the same layout and it appears automatically in
`mkproj --list-templates`. Global files (not project-specific) live in `templates/global/`.

## Tests

    bash tests/test-input.sh
    .venv/bin/python -m unittest discover -s tests -p 'test_reliability.py' -v
    mkproj --test

The input suite covers malformed inputs and length boundaries. Regression tests
exercise collisions, failure injection, backup permissions, native Git guards,
read-only modes, archive collisions, and user-file preservation.
The scaffold test uses a disposable root for both repositories and its venv,
never edits user-global configuration, never pushes, and cleans up on failure.

## Install and customize

Requires Linux, Bash 4.3+, Python 3.12+ with venv support, Git, jq, and flock.
screen is needed for interactive screen launch; the selected agent must be installed.
The installer supports apt-based Linux systems. Windows compatibility is deferred.

    bash install.sh --check
    bash install.sh

Edit `templates/claude-code/` for future projects. Behavioral rules belong in
`templates/claude-code/project/CLAUDE.md`; `templates/claude-code/project/AGENTS.md`
only points to that file. Do not rerun bootstrap on a live project to migrate its
configuration.

See docs/usage.md, docs/reliability.md, and docs/customizing.md.
