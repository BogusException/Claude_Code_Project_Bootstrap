# Changelog

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
