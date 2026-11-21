# Changelog

## [3.0.0] - (pending release)

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
