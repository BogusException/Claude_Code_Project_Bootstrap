# Customizing

## 1. Changing what new projects receive

Every file bootstrap copies from `templates/` can be edited directly. Changes take effect on the next `mkproj` run -- no reinstall needed.

| To change | Edit |
|-----------|------|
| Default `.gitignore` | `templates/.gitignore` |
| Default `.gitattributes` | `templates/.gitattributes` |
| Standing Claude instructions | `templates/CLAUDE.md` |
| `.env.example` format | `templates/.env.example` |
| `run.sh` / `test.sh` patterns | `templates/run.sh`, `templates/test.sh` |
| `save-response.sh` behaviour | `templates/hooks/save-response.sh` |
| `auto-commit.sh` behaviour | `templates/hooks/auto-commit.sh` |
| Doc stubs new projects get | `templates/docs/*.md` |

## 2. Adding a new bootstrap phase

1. Add a `phaseN_name()` function to `bootstrap.sh`
2. Call it in `main()` in the correct order
3. Include an idempotency guard (check before creating/writing)
4. Add a row to the phase table in `docs/how-it-works.md §3`

## 3. Changing the command name

Edit `install.sh` -- change the `LAUNCHER` variable at the top, then re-run it:

```bash
bash ~/Projects/project-bootstrap/install.sh
```

## 4. Disabling branch protection for a repo

`block-dangerous-commands.sh` prevents pushes to `main` by default -- appropriate for team projects, but not for single-developer repos.

### 4.1 Disable protection entirely

```bash
touch .claude/protected-branches   # empty file = no protected branches
```

### 4.2 Protect specific branches other than main/master

```bash
echo "main" > .claude/protected-branches
echo "release" >> .claude/protected-branches
```

The file is read at hook-run time, so changes take effect immediately without restarting Claude Code.

## 5. Maintaining bundled hooks

All hook scripts are bundled in templates/hooks/. Update those files deliberately; bootstrap does not depend on an installed marketplace.

## 6. Adding custom hooks to all new projects

1. Place the hook script in `templates/hooks/`
2. The existing wildcard copy loop in `phase5_claude_config()` in `bootstrap.sh`
3. Add the corresponding entry to `generate_settings_json()` with the correct event type and matcher

## 7. Codex and shared project directives

New projects receive an AGENTS.md entry point that directs Codex to CLAUDE.md.
Edit templates/CLAUDE.md for both agents' behavior and its Codex-specific section
for differences in tooling. No user-level Codex configuration is required for
this entry point. Codex discovers AGENTS.md when a new session starts:
https://learn.chatgpt.com/docs/agent-configuration/agents-md

The adapter covers Git workflow, project venv selection, private exchange
archiving, and verified configuration backups. Claude hooks and permission
settings remain Claude-specific; this does not install equivalent Codex hooks
or change either tool's status settings. Bootstrap still launches Claude Code;
Codex can be opened separately in the generated project.

For an existing project, back up its configuration first, add the AGENTS.md
entry point, and merge shared directive changes deliberately. Do not rerun
mkproj on a live project or overwrite its CLAUDE.md with the template.

All of responses/ is ignored, with no tracked placeholder. Filesystem backups
are ignored at every depth. Before modifying existing global configuration,
bootstrap creates a timestamped, verified copy beside it in backups/, preserving
file metadata. These are local recovery copies; keep a separate backup against
loss of the underlying storage.

See reliability.md for native Git guards, read-only modes, staged-only auto-commit, and opt-in global setup.
