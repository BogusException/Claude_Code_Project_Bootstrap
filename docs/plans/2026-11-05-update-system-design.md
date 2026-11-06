# Design: mkproj v2 -- project identity, update, and scan

Date: 2026-11-05
Status: approved for implementation

## Background

mkproj is currently a one-shot bootstrapper. It has no memory of what it
installed, no way to identify previously bootstrapped projects, and no update
path. This design adds those capabilities while preserving the non-destructive
conventions already in the codebase.

---

## 1. Project identity -- the `.mkproj` marker file

Every bootstrapped project gets `.mkproj` in its root (not a directory -- just
the file). It is JSON, human-readable, and gitignored.

```json
{
  "format": 1,
  "mkproj_version": "2.0.0",
  "installed_at": "2026-11-05T21:00:00Z",
  "updated_at": "2026-11-05T21:00:00Z",
  "files": {
    "CLAUDE.md": {
      "template_hash": "abc...",
      "installed_hash": "abc...",
      "status": "installed"
    }
  },
  "components": ["core", "venv", "docs", "tasks", "hooks", "rules", "settings"]
}
```

Fields:
- `format`: schema version integer (currently 1)
- `mkproj_version`: semver of the mkproj tool that last ran
- `installed_at`: ISO 8601 timestamp of initial bootstrap
- `updated_at`: ISO 8601 timestamp of last run
- `files`: per-file tracking dict (see below)
- `components`: list of installed component groups

### File tracking

Each entry in `files` maps a project-relative path to:
- `template_hash`: SHA-256 of the template at install/update time
- `installed_hash`: SHA-256 of what was actually written to disk
- `status`: one of `installed`, `deferred`, `skipped`

### Decision rules

| File on disk? | In `files`? | Template changed? | File changed? | Action |
|---|---|---|---|---|
| absent | yes (installed) | any | any | User deleted. Skip, log, never reinstall. |
| absent | no | -- | -- | New template file. Install unconditionally. |
| present | no | -- | -- | New template file. Install unconditionally. |
| present | yes | no | no | Nothing changed. Skip silently. |
| present | yes | yes | no | Template updated, file untouched. Auto-update. |
| present | yes | no | yes | User customized. Skip (their edits). |
| present | yes | yes | yes | Conflict. Show diff, prompt for decision. |

### Conflict decision UI

```
─────────────────────────────────────────────────────
  [conflict]  .claude/settings.json
  Project:    /home/pat/Projects/my-project
  ─────────
  TEMPLATE (new):
  <first 10 lines of unified diff, truncated if longer>
  ─────────
  [u] Update to new template version
  [k] Keep your version unchanged
  [d] Defer this decision (revisit with --pending)
  [s] Stop reviewing; leave all remaining for later
  
  Choice [u/k/d/s, default=d]:
─────────────────────────────────────────────────────
```

Non-interactive (`--yes`): auto-select `k` on all conflicts.

### Deletion behavior

If a file appears in `files` with status=`installed` but is absent from disk,
the user deleted it. mkproj logs one line and moves on. It will never reinstall
that file unless the user removes the entry from `.mkproj` by hand.

---

## 2. Component groups

| Group | Contents |
|---|---|
| `core` | CLAUDE.md, AGENTS.md, .gitignore, .gitattributes, .env.example |
| `venv` | Python venv, requirements.txt, run.sh, test.sh |
| `docs` | docs/ stub files |
| `tasks` | tasks/ stub files |
| `hooks` | .claude/hooks/ scripts |
| `rules` | .claude/rules/ files |
| `settings` | .claude/settings.json |
| `git-hooks` | .git/hooks/ scripts |
| `keybindings` | ~/.claude/keybindings.json (global, opt-in with --keybindings) |

---

## 3. New CLI modes and flags

### Modes

| Flag | What it does |
|---|---|
| `--version` | Print mkproj version and exit |
| `--update [name]` | Update one project (current dir if no name) |
| `--scan [dir]` | Recurse, update every mkproj project found (default dir: $PWD) |
| `--status [dir]` | Dry-run scan: one line per project showing version comparison |
| `--pending [dir]` | Find and interactively resolve all deferred decisions |
| `--adopt [name]` | Enroll a non-mkproj Claude Code project minimally |

### Flags usable across modes

| Flag | Effect |
|---|---|
| `--keybindings` | Enable keybindings install in phase 7 (default: off) |
| `--dry-run` | Show what would change without changing anything |
| `--yes` / `-y` | Accept all non-conflict updates without prompting |
| `--quiet` / `-q` | Suppress informational output |
| `--verbose` / `-v` | Show per-file decisions including up-to-date skips |

---

## 4. `--status` output format

```
mkproj --status ~/Projects

Managed projects (4):
  project-bootstrap   installed 2.0.0  current 2.0.0  up to date
  ping-watch          installed 1.9.0  current 2.0.0  2 files changed, 1 conflict
  syncro              installed 2.0.0  current 2.0.0  up to date

Claude Code projects (not managed, 2):
  agency-agents       has .claude/ but no .mkproj  -- run: mkproj --adopt agency-agents

Unknown (skipped, 87):
  sandbox, llmChat, _temp, ...
```

Exit code 2 when any conflicts or pending decisions exist.

---

## 5. `--adopt` behavior

Detection of a Claude Code project: directory has `.claude/settings.json` OR
`CLAUDE.md`.

What `--adopt` does (additive only, never overwrites):
1. Creates `.mkproj` with empty `files` and `"components": ["adopted"]`
2. Adds missing `.gitignore` privacy guards (responses/, backups/, .env)
3. Adds `AGENTS.md` if absent
4. Does NOT touch anything already present

When `--scan` finds a non-mkproj Claude Code project, it presents it
separately and offers to adopt interactively.

---

## 6. Retroactive stamping

When `--update` or `--scan` encounters a project that has mkproj markers
(CLAUDE.md + AGENTS.md + .claude/settings.json) but no `.mkproj`, it
auto-creates `.mkproj` by computing hashes from current on-disk state. This
records all existing files as "installed at their current state" so the first
real update run does not flag everything as a conflict.

---

## 7. Man-page style `--help`

The help output will use this structure, paged through `less` on a TTY:

```
NAME
SYNOPSIS
DESCRIPTION
OPTIONS
MODES
FILES
EXIT STATUS
ENVIRONMENT
EXAMPLES
```

Output uses no ANSI escape codes (must be readable via SSH from any terminal).

---

## 8. `MKPROJ_VERSION` constant

Add `MKPROJ_VERSION="2.0.0"` near the top of `bootstrap.sh`. Bump on each
release. Used in `.mkproj` files and `--version` output.

---

## 9. `.mkproj` added to .gitignore

Add `.mkproj` to:
- `templates/.gitignore` (new projects)
- The gitignore-patching logic in phase 1 (existing projects, via `--update`)

---

## 10. `--scan` scope rules

Recurse all subdirectories except:
- `.git/`
- `node_modules/`
- `.venv/`
- `__pycache__/`
- Directories named `backups/` or `responses/`

Default depth: unlimited. Future: `--max-depth N` (TODO).

---

## 11. Windows

Claude Code is Linux-native. WSL2 is the correct path for Windows users:
1. `wsl --install` on Windows 10/11
2. Claude Code inside WSL2 is identical to bare Linux
3. mkproj works unchanged inside WSL2
4. Windows Terminal handles Alt keys correctly (Alt+S submit binding works)

A native Windows port would require a full PowerShell rewrite. Not planned.

---

## 12. Items deferred to TODO.md

- `--update --components=hooks,rules` selective component updates
- `--max-depth N` for scan depth control
- `--force` to auto-accept template on conflicts (skipped intentionally; too dangerous without audit trail)
- Component-level adoption options in `--adopt`
- Machine-readable output (`--json`) for scripting
- `mkproj --init` alias for setup (to match `git init` muscle memory)
