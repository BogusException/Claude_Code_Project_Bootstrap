# Changelog

## [3.2.0] - 2026-11-22 -- CRC32(bootstrap.sh) `e39fdc13`

### Added
- `mkproj migrate [DIR] [--apply]`: upgrades a v2.x `.mkproj` registry to v3 format without touching any project file. Dry-run by default -- prints a per-file classification table (unchanged / template_changed / user_edit / both_changed / gone_on_disk / orphan) and tier assignments. Pass `--apply` to stamp tier fields, refresh unchanged template hashes, bump `mkproj_version`, and write an audit log to `responses/internal/migration-changelog-<project>.txt`.

### Fixed
- **Defect 1 (G-009 root cause)**: `TEMPLATE_DIR` was never set for maintenance modes (`check`, `scan`, `status`, `pending`, `safe-update`, `report`, `restore-infra`, `list-tiers`). `template_to_project_path` stripped nothing, causing all tracked files except `.claude/settings.json` to silently drop. Fixed by resolving `TEMPLATE_DIR` from `.mkproj` or the default template in `initialize()` before the early-return for maintenance modes. `mkproj tiers ~/Projects/pfsense_wazuh` now visits 36 files (was 1).
- **Defect 2**: `project_to_template_path` in `lib/update.sh` referenced flat v2 layout paths (`templates/hooks/`, `templates/rules/`) which do not exist in v3. Rewrote as exact inverse of `template_to_project_path` using `$TEMPLATE_DIR/claude/hooks/`, `claude/rules/`, `claude/skills/`, `git-hooks/`, `project/`.
- **Defect 3**: git hooks key mismatch -- `project_to_template_path` mapped `.git/hooks/*` but v3 canonical path is `.githooks/*`. Corrected.

## [3.1.3] - 2026-11-22 -- CRC32(bootstrap.sh) `e6daf010`

### Fixed
- `mkproj scan` did not follow symbolic links, so a staging directory of symlinked candidates showed up empty. Added `-L` to both `find` invocations in `scan_projects` (`lib/update.sh:577,587`).
- `release.sh` created the git tag and pushed the commit but silently skipped `gh release create`, because the awk range pattern `/^## \[$VERSION\]/,/^## \[/` tested the end regex against the start line and closed immediately, leaving `NOTES` empty and the gh call with no release body. Rewrote the extraction with explicit state tracking, and added a hard-fail if `gh release create` returns non-zero so the next silent failure surfaces.

## [3.1.2] - 2026-11-22 -- CRC32(bootstrap.sh) `b3270103`

### Fixed
- `mkproj adopt` ran through `phase1_preflight`, which refused any project with real commit history ("STOP: project contains real project commits") — but refusing real history is exactly backwards for a command whose job is enrolling existing projects. Moved `adopt` to the top-level dispatcher so it skips the bootstrap-mode preflight. (G-010)
- `adopt_project()` tried to install `AGENTS.md` from a stale v2 template path (`$TEMPLATES_DIR/AGENTS.md`, no longer exists under the v3 multi-template layout) and did so unconditionally, forcing Codex's directive file into every adopted project regardless of the user's agent choice. Rewrote to only record directive files that already exist in the project, matching the user's agent-choice principle (TODO-D). (G-011)

## [3.1.1] - 2026-11-22 -- CRC32(bootstrap.sh) `4ceb4569`

### Fixed
- `mkproj scan`, `check`, `status`, `pending`, `safe-update`, `report`, `restore-infra`, and `list-tiers` all failed in v3.1.0 because of two bugs (gotcha G-003). First, an `&& ... = "$PWD"` one-liner in `lib/input.sh` returned non-zero when a DIR argument was passed, which propagated as `parse_args` returning 1 under `set -e`. Second, these maintenance modes fell through to `main()`, which ran `phase1_preflight` before the mode dispatch, and preflight read an unset `PROJECT_NAME` under `set -u`. Fixed by converting the `&&` to an `if` block and dispatching maintenance modes at the top-level case before `main()` is called.

## [3.1.0] - 2026-11-22 -- CRC32(bootstrap.sh) `f8725367`

### Added
- Command-form syntax: `mkproj update`, `scan`, `check`, `diagnose`, `restore`, `tiers`, `preview`, `adopt`, `pending`, `status`, `test`, `version`, `help`. Legacy `--option` form still accepted.
- `docs/governance.md`: third-party isolation policy. Clarifies that project-bootstrap owns its own hooks only and is not responsible for patching third-party tools.
- `--safe` option on `mkproj update` (equivalent to legacy `safe-update` mode).

### Fixed
- `save-response.sh`: transcript scan now reads backward from end, fixing high-context Stop hook latency.
- `scan-secrets.sh`: responses/ directory excluded from secret scans (false positives on archived chat text).
- bootstrap.sh execute permission restored (was 644, caused exit 126).

## [3.0.2] - 2026-11-21 -- CRC32(bootstrap.sh) `6b68ba14`

### Changed
- README: two primary commands at the very top, explanatory line, full grouped command reference immediately below.
- README: added both run modes (parent-dir and adopt-current-dir) with naming rules.
- README: expanded command reference with all current flags grouped by use case.
- tasks/todo.md: all v3.0.0 and v3.0.1 tasks checked off; `--prune` logged as deferred feature.
- .gitignore: added `reference/` to cover private local notes.

### Maintenance
- Removed duplicate "Release v3.0.0" commit from history via rebase.
- Retagged v3.0.0 and v3.0.1 to correct post-rebase commits on both remotes.

## [3.0.1] - 2026-11-21 -- CRC32(bootstrap.sh) `766f806a`

### Fixed
- Replace developer-specific absolute home path with generic placeholder in design doc example.
- Update stale GitHub handle to current `BogusException` in bootstrap.sh manpage and impl doc.
- Remove `--no-index` from `git check-ignore` in `guard_path()` so tracked files inside template
  `responses/` subdirectories are not blocked by sub-directory `.gitignore` patterns.
- Fix `.githooks/pre-commit` and `.githooks/pre-push` delegating to old `templates/git-hooks/` path.

### Added
- `/scan` skill bundled in every new project: checks for absolute paths, personal identifiers,
  API key patterns, gitignore misses, and email addresses. Reports findings with severity levels.

### Docs
- All docs updated for v3.0.0 multi-template architecture (template paths, new flags, skills).
- `overview.md` and `README.md` now have a "non-obvious capabilities" section explaining Git-level
  guards, update tracking, file tiers, locked access, staged-only auto-commit, and skills.
- `doc-index.md` updated with entries for skills, `--template`, `--list-templates`, tiers, and
  new maintenance flags.

## [3.0.0] - 2026-11-21 -- CRC32(bootstrap.sh) `23d1dae5`

### Breaking changes
- `templates/` directory restructured into named template folders (`templates/claude-code/`).
  Forks or customizations of the flat `templates/` layout must be migrated.

### Added
- Multi-template architecture: templates live under `templates/<name>/` with `project/`,
  `claude/`, and `git-hooks/` subtrees.
- `templates/.default` file names the default template.
- Interactive template selection at `mkproj` run time: numbered list, default sorted first,
  `[N - name]` bracket in prompt, Enter accepts default.
- `--template NAME` flag to select a template non-interactively.
- `--list-templates` flag to print available templates and exit.
- `/audit` skill bundled in every new project (`.claude/skills/audit.md`).
- `docs/skills.md` in every new project explaining available skills.
- End-of-run tip line pointing users to `/audit` once they have a working draft.
- `templates/global/` for user-scoped installs (keybindings.json).
- `install.sh` now offers opt-in global install of `/audit` skill to `~/.claude/skills/`.
- `CHANGELOG.md`, `release.sh`, `RELEASING.md` added to this repository.

### Changed
- `bootstrap.sh` template-install phases rewritten as tree walkers; scattered
  `copy_template` and `mkdir -p` calls replaced with `install_project_tree`,
  `install_claude_tree`, `install_git_hooks`.
- `lib/input.sh` extended with `list_templates` and `prompt_template_select`.
- `templates/global/keybindings.json` replaces `templates/keybindings.json`.

### Removed
- `templates/backups/` subdirectories (edit artifacts, not template content).

---

## [2.1.0] - 2026-10-21

- Allow hyphens in project names; derive Python module name with underscores.
- Document non-interactive usage and hyphen name support.

## [2.0.0] - 2026-11-05

- File tier system: directive/infrastructure/optional with `--check`, `--safe-update`,
  `--report`, `--force-file`, `--accept`, `--restore-infra`, `--list-tiers`.
- `.mkproj` registry tracking template_hash and installed_hash per file.
- `--update`, `--scan`, `--status`, `--pending`, `--adopt` modes.
- Man-page style `--help` with pager. `--version` flag.
- Five new registry validation tests.

## [1.x] - 2026-08 through 2026-10

- Initial scaffold, `--test` mode, bare repo prompt, hooks/rules bundled in templates,
  name validation, Linux reliability hardening, Codex compatibility, keybindings install.
