# Customizing

## 1. Template structure

Templates live under `templates/<name>/` with three subtrees:

| Subtree | Destination in new project |
|---------|--------------------------|
| `templates/<name>/project/` | project root (verbatim or with `{{PROJECT_NAME}}` / `{{MODULE_NAME}}` substitution) |
| `templates/<name>/claude/hooks/` | `.claude/hooks/` |
| `templates/<name>/claude/rules/` | `.claude/rules/` |
| `templates/<name>/claude/skills/` | `.claude/skills/` |
| `templates/<name>/git-hooks/` | `.githooks/` |

The default template is `claude-code`. The file `templates/.default` names it. Global files not tied to any template live in `templates/global/`.

To list available templates:

    mkproj --list-templates

To create a project with a specific template:

    mkproj --template mytemplate my_tool

## 2. Changing what new projects receive

Edit files directly inside the template subtree. Changes take effect on the next `mkproj` run.

| To change | Edit |
|-----------|------|
| Default `.gitignore` | `templates/claude-code/project/.gitignore` |
| Default `.gitattributes` | `templates/claude-code/project/.gitattributes` |
| Standing Claude instructions | `templates/claude-code/project/CLAUDE.md` |
| `.env.example` format | `templates/claude-code/project/.env.example` |
| `run.sh` / `test.sh` patterns | `templates/claude-code/project/run.sh`, `test.sh` |
| `save-response.sh` behaviour | `templates/claude-code/claude/hooks/save-response.sh` |
| `auto-commit.sh` behaviour | `templates/claude-code/claude/hooks/auto-commit.sh` |
| Doc stubs new projects get | `templates/claude-code/project/docs/*.md` |
| Skills installed in new projects | `templates/claude-code/claude/skills/` |
| Keybindings (global, optional) | `templates/global/keybindings.json` |

## 3. Adding a new bootstrap phase

1. Add a `phaseN_name()` function to `bootstrap.sh`
2. Call it in `main()` in the correct order
3. Include an idempotency guard (check before creating/writing)
4. Add a row to the phase table in `docs/how-it-works.md §3`

## 4. Changing the command name

Edit `install.sh` -- change the `LAUNCHER` variable at the top, then re-run it:

```bash
bash ~/Projects/project-bootstrap/install.sh
```

## 5. Disabling branch protection for a repo

`block-dangerous-commands.sh` prevents pushes to `main` by default -- appropriate for team projects, but not for single-developer repos.

### 5.1 Disable protection entirely

```bash
touch .claude/protected-branches   # empty file = no protected branches
```

### 5.2 Protect specific branches other than main/master

```bash
echo "main" > .claude/protected-branches
echo "release" >> .claude/protected-branches
```

The file is read at hook-run time, so changes take effect immediately without restarting Claude Code.

## 6. Maintaining bundled hooks

All hook scripts are bundled in `templates/claude-code/claude/hooks/`. Update those files directly; bootstrap does not depend on an external marketplace.

## 7. Adding custom hooks to all new projects

1. Place the hook script in `templates/claude-code/claude/hooks/`
2. The tree-walker in `install_claude_tree()` in `bootstrap.sh` picks it up automatically
3. Add the corresponding entry to `generate_settings_json()` with the correct event type and matcher

## 8. Adding a new template

1. Create `templates/<name>/` with `project/`, `claude/`, and `git-hooks/` subtrees
2. Populate them following the same layout as `templates/claude-code/`
3. Use `.gitkeep` files to preserve empty directories
4. It appears automatically in `mkproj --list-templates` and `mkproj --template <name>`

To make it the default, update `templates/.default`:

```bash
echo "mytemplate" > templates/.default
```

## 9. Codex and shared project directives

New projects receive an AGENTS.md entry point that directs Codex to CLAUDE.md.
Edit `templates/claude-code/project/CLAUDE.md` for both agents' behavior and its Codex-specific section
for differences in tooling. No user-level Codex configuration is required for
this entry point.

The adapter covers Git workflow, project venv selection, private exchange
archiving, and verified configuration backups. Claude hooks and permission
settings remain Claude-specific. Bootstrap still launches Claude Code;
Codex can be opened separately in the generated project.

For an existing project, back up its configuration first, add the AGENTS.md
entry point, and merge shared directive changes deliberately. Do not rerun
mkproj on a live project or overwrite its CLAUDE.md with the template.

See reliability.md for native Git guards, read-only modes, staged-only auto-commit, and opt-in global setup.
