# v3.0.0 -- Multi-template architecture

## Goal
Replace the single flat `templates/` directory with a named-template system.
Each template is a self-contained folder under `templates/` with a `project/`
subtree (copied to project root) and a `claude/` subtree (installed into `.claude/`),
plus a `git-hooks/` subtree (installed into `.git/hooks/`). A `templates/.default`
file names the default template. `bootstrap.sh` becomes a walker, not a file-by-file
copier. New interactive template selection prompt at mkproj run time.

## Tasks

- [ ] 1. Create CHANGELOG.md with history back-filled from git log
- [ ] 2. Create release.sh (read VERSION, verify tag, run tests, stamp CRC, commit, push, gh release)
- [ ] 3. Create RELEASING.md pre-flight checklist
- [ ] 4. Reorganize templates/ into new tree:
        templates/.default  (contains "claude-code")
        templates/global/   (keybindings.json -- installed globally, not per-project)
        templates/claude-code/project/   (full project root mirror, empty dirs get .gitkeep)
        templates/claude-code/claude/    (hooks/, rules/, skills/, settings.json)
        templates/claude-code/git-hooks/ (pre-commit, pre-push, private-paths.sh)
        Drop all backups/ subdirectories inside templates/ (edit artifacts, not content)
- [ ] 5. Add /audit SKILL.md to templates/claude-code/claude/skills/
- [ ] 6. Add docs/skills.md to templates/claude-code/project/docs/ explaining /audit
- [ ] 7. Rewrite bootstrap.sh template-install phases:
        - read_template_name(): reads .default, respects --template flag
        - install_project_tree(): walks project/ and copies to PROJECT_DIR, substituting macros
        - install_claude_tree(): walks claude/ and installs into .claude/
        - install_git_hooks(): walks git-hooks/ and installs into .git/hooks/
        - install_global(): installs templates/global/ items (keybindings.json) with existing logic
        - Remove all scattered mkdir -p and copy_template calls replaced by walkers
- [ ] 8. Add interactive template selection to lib/input.sh:
        - list_templates(): scans templates/, reads .default, sorts default first
        - prompt_template_select(): numbered list, [N - name] bracket, Enter accepts default
        - --template NAME flag: skip prompt, validate name exists
        - --list-templates flag: print list and exit
- [ ] 9. Add end-of-mkproj tip line pointing to /audit and docs/skills.md
- [ ] 10. Add global /audit install option to install.sh (opt-in, [Y/n] prompt with ? for less view)
- [ ] 11. Bump MKPROJ_VERSION to 3.0.0
- [ ] 12. Run full test suite -- fix any failures before continuing
- [ ] 13. Stamp CHANGELOG, commit "Release v3.0.0", push, gh release create

## Deferred from v2.0.0 (carry forward)

- [ ] `--update --components=hooks,rules` selective component updates
- [ ] `--max-depth N` for scan depth control
- [ ] `--force` flag (requires audit trail before overwriting user edits)
- [ ] Component-level options in `--adopt`
- [ ] `--json` machine-readable output for scripting
- [ ] `mkproj --init` alias for the default bootstrap mode
- [ ] Windows native support (WSL2 recommended in the interim)
- [ ] `mkproj --diff NAME` -- show pending changes without updating

## Validation baseline

182 input/boundary/no-side-effect checks and 27 Linux regression tests pass.
The regression suite includes the isolated full scaffold test, forced private
staging, private history later deleted, push failure, backup failure, launcher
failure, collision/ref preservation, archive collisions, and venv switching.
Bash syntax and git diff whitespace checks pass.
