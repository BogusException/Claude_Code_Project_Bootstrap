# How it works

The installed ~/bin/mkproj launcher delegates to bootstrap.sh.
lib/input.sh validates bounded arguments/prompts; lib/runtime.sh implements
backups, Git preflight, private-path guard installation, and read-only diagnostics.

Setup validates the target and confirms the plan before mutation, then obtains
project and bare-destination locks. It creates Git/venv/scaffold files, installs
native private-path guards, verifies configuration/privacy/venv, installs project
dependencies, optionally configures globals, and commits only generated files.
Verification precedes commit/push. Finally it releases locks and launches the
selected agent, or exits for --agent=none.

templates/ contains all copied project material, including Claude hooks,
Git hooks, shared CLAUDE.md, and the AGENTS.md entry point.
.claude/hooks are agent hooks; .githooks are native Git guards. They are different.

--test creates its entire scaffold and bare repo beneath one temporary root,
isolates Git identity/configuration, skips pushes and global changes, and cleans
up using an EXIT trap. Errors report the failing phase and return nonzero.

install.sh --check inspects prerequisites without installation. Normal installation
backs up replaced launchers and tests a candidate before publishing it.
See reliability.md for invariants and recovery details.
