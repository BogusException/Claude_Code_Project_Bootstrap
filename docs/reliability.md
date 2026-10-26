# Linux reliability and recovery

## Read-only and test modes

--dry-run validates inputs and inspects the target before printing a plan. It
does not create project files, install packages, configure globals, or push.
--doctor reports prerequisites, the project venv, ignore protection, native Git
guards, working-tree state, and all origin push destinations. Blocking findings produce
a nonzero exit status; optional missing agents are reported separately.

--test uses a mktemp directory beneath TMPDIR (or /tmp), including the local
project, bare repository, locks, and venv. It isolates Git identity/configuration,
does not push, skips global configuration, and cleans up on success or failure.
tests/test_reliability.py exercises additional regression and failure paths.

## Git and privacy

Both this repository and generated projects ignore all of responses/ and backups/
at every depth, venvs, secrets, keys, runtime artifacts, and local agent state.
.env.example remains trackable. Native hooks reject private or ignored index entries and
private paths in new outgoing commit history, including files later deleted.
Only empty historical responses/.gitkeep entries are grandfathered for existing
repository history. New response placeholders are rejected.

These are path-based guards, not a general secret scanner. Deliberate --no-verify
can bypass native hooks. Existing history is not rewritten by this update.
A staged-only Stop hook prevents unrelated untracked/unstaged files from being
swept into automatic commits. Commit and push errors are reported.

Bootstrap stages only files it generated in the current run. It refuses
pre-existing staged changes, dirty tracked files, detached HEAD, live-project
commits, merge state, nested repos, remote changes, non-bare destinations,
and bare collisions. Matching origin/heads/tags can resume. Existing custom
native hooks or hooksPath require explicit integration, not silent replacement.

Project and bare-destination locks prevent concurrent bootstrap writers.
Scaffold verification and project-venv dependency installation finish before
commit/push. Failed phases report their phase and retain the project for inspection.

## Configuration backups and recovery

Existing configuration is copied into an adjacent backups/ directory using
cp --preserve=all and verified with cmp before replacement. Names include
date, time, and nanoseconds. Replacements use a temporary file in the same
directory and atomic rename while retaining original file metadata. Symlinked
configuration replacement is refused.

install.sh smoke-tests a candidate launcher before replacing the existing one,
backs up its old contents, and retains the legacy proj alias.
Global hook/shell setup is optional and defaults to No. It preserves unrelated
JSON fields, including status settings. Existing custom hooks/configuration
are retained rather than overwritten.

To recover, identify the timestamped backup, review it, back up the current file,
and copy the chosen backup back with cp --preserve=all. Do not overwrite a backup.
Keep separate storage-level backups: adjacent copies do not survive disk loss.
Git is not a backup.

## Archives and agents

Claude and Codex share CLAUDE.md; AGENTS.md is an entry point. Their tooling and
status/model settings remain distinct. The archive hook uses the project venv,
creates files exclusively to prevent same-second overwrites, verifies readback,
and atomically updates .last-saved. Missing queries or failed writes are reported.
Codex saves/reads its exchanges directly under the shared directive.

## Scope

Linux is the current target. Windows compatibility and cross-platform shell
behavior are deferred. Existing projects need deliberate migrations; copying
new templates over a live project's configuration is not supported.
