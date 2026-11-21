# Tier System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use godmode:task-runner to implement this plan task-by-task.

**Goal:** Add a file trust tier system (directive / infrastructure / optional) to mkproj so update operations are safe, transparent, and correctly scoped by file importance.

**Architecture:** A manifest file declares a tier for every template file. The registry stores tier per file at install time. The update engine uses tier to decide whether to auto-apply, flag loudly, or stay silent. New CLI flags give users graduated control from read-only audit through safe auto-update to forced conflict resolution.

**Tech Stack:** bash, jq, mkproj (bootstrap.sh + lib/), .mkproj JSON registry per project.

---

### Task 1: templates/.mkproj-manifest.json

**Files:**
- Create: `templates/.mkproj-manifest.json`

**Acceptance criteria:**
- Every file in `templates/` has an explicit entry.
- `default_tier` is `"optional"`.
- `directive` tier: `CLAUDE.md`, `AGENTS.md`.
- `infrastructure` tier: all hooks, settings.json, git-hooks, rules/, .gitignore, .gitattributes.
- `optional` tier: docs/, tasks/, README.md, run.sh, test.sh, requirements.txt, .env.example.

**Verify:**
```bash
jq empty templates/.mkproj-manifest.json && echo "valid JSON"
jq '.files["CLAUDE.md"].tier' templates/.mkproj-manifest.json   # expect "directive"
jq '.files[".claude/hooks/save-response.sh"].tier' templates/.mkproj-manifest.json  # expect "infrastructure"
jq '.files["README.md"].tier' templates/.mkproj-manifest.json   # expect "optional"
```

---

### Task 2: lib/registry.sh -- tier storage

**Files:**
- Modify: `lib/registry.sh`

**Changes:**
1. `registry_set_file` gains optional 6th arg `TIER`. If omitted, resolves from `$MANIFEST_FILE` or defaults to `optional`.
2. `registry_file_tier PROJECT_DIR REL_PATH` -- reads tier from `.mkproj`; falls back to manifest; falls back to `optional`.
3. `registry_stamp_from_disk` -- reads tier from manifest when stamping adopted projects.
4. `registry_stamp_from_disk` -- excludes `.mkproj-manifest.json` from tracked files.

**Verify:**
```bash
bash -n lib/registry.sh && echo "syntax ok"
```

---

### Task 3: lib/update.sh -- tier-aware decisions

**Files:**
- Modify: `lib/update.sh`

**Changes:**
1. `load_manifest` -- validates `$MANIFEST_FILE` is set, exists, and is valid JSON. Warns if not, never hard-fails.
2. `file_tier REL_PATH` -- returns tier from manifest (or `optional`).
3. `file_update_decision` new return values:
   - `skip_deleted_optional` -- was optional, user deleted, stay silent forever.
   - `skip_deleted_infra` -- infrastructure deleted, flag in report, offer `--restore-infra`.
   - `skip_deleted_directive` -- directive deleted, loud ERROR, block auto operations.
   - `conflict_directive` -- directive conflict (both changed, or template-only change on directive).
4. Directive files: template-only change is downgraded from `auto_update` to `conflict_directive` (never silently overwrite directives).
5. `show_conflict_ui` -- prints tier consequence line before diff:
   - directive: yellow WARNING line.
   - infrastructure: "generally safe" note.
6. `_handle_update_decision` respects `SAFE_MODE`: only applies `auto_update` on `infrastructure` files.
7. `apply_template_file` -- passes tier to `registry_set_file`.

**Verify:**
```bash
bash -n lib/update.sh && echo "syntax ok"
```

---

### Task 4: bootstrap.sh -- new mode flags and MANIFEST_FILE

**Files:**
- Modify: `bootstrap.sh`

**Changes:**
1. Set `MANIFEST_FILE="$BOOTSTRAP_DIR/templates/.mkproj-manifest.json"` after `BOOTSTRAP_DIR`.
2. Call `load_manifest` before any update/scan/check operation.
3. New globals: `SAFE_MODE=false`, `CHECK_MODE=false`, `REPORT_MODE=false`, `FORCE_FILE=""`, `ACCEPT_FILE=""`, `RESTORE_INFRA_MODE=false`, `LIST_TIERS_MODE=false`.
4. Arg parsing: add `--safe-update`, `--check`, `--report`, `--force-file`, `--accept`, `--file`, `--restore-infra`, `--list-tiers`.

**Verify:**
```bash
bash -n bootstrap.sh && echo "syntax ok"
mkproj --help | grep -E "safe-update|check|report|force-file|accept|restore-infra|list-tiers"
```

---

### Task 5: bootstrap.sh -- `--check` mode

**Behaviour:**
- Read-only. Walks all tracked files. Prints ERRORs for directive problems, WARNINGs for infrastructure problems, silence for optional.
- Exit 0 = clean, 1 = warnings only, 2 = errors present.

**Output format:**
```
[ERROR] CLAUDE.md -- directive file deleted. Run: mkproj --report <dir>
[WARNING] .claude/hooks/save-response.sh -- infrastructure file deleted.
[WARNING] .claude/settings.json -- infrastructure conflict (template updated, local modified).
```

**Verify:**
```bash
bash -n bootstrap.sh && echo "syntax ok"
# In a test project: delete CLAUDE.md, run mkproj --check; expect exit 2.
# Delete a hook; expect exit 1 (warning only, no directive issues).
```

---

### Task 6: bootstrap.sh -- `--safe-update` mode

**Behaviour:**
- Auto-applies `auto_update` decisions for `infrastructure` tier only.
- Never modifies directive files, never restores deleted optionals.
- If directive problems exist, prints them and exits non-zero even if safe updates succeeded.
- Compatible with `--yes` and `--quiet`.

**Verify:**
```bash
mkproj --safe-update --dry-run <project>  # no writes
mkproj --safe-update --quiet <project>    # only action lines printed
```

---

### Task 7: bootstrap.sh -- `--report` mode

**Behaviour:**
- Writes `mkproj-issues-YYYYMMDD-HHMMSS.md` to the project directory.
- One `##` section per issue: tier, status, risk-if-left, exact fix command, manual steps.
- Uses atomic write (mktemp + mv).
- Prints path to written file.
- Exit 0 always (report is informational).

**Output format per issue:**
```markdown
## [ERROR] CLAUDE.md -- directive file deleted

**Tier:** directive
**Status:** deleted
**Risk if left unresolved:** Agent loses project-specific behavioral directives permanently.

**To restore from template (overwrites any manual recovery):**
    mkproj --force-file CLAUDE.md <project_dir>

**To silence this permanently (you are managing it yourself):**
    mkproj --accept <project_dir> --file CLAUDE.md

**Manual steps:** Restore from git history or recreate from templates/CLAUDE.md.
```

**Verify:**
```bash
bash -n bootstrap.sh
# Delete CLAUDE.md in test project, run mkproj --report, verify file written and readable.
```

---

### Task 8: bootstrap.sh -- `--force-file` and `--accept`

**`--force-file REL_PATH`** (only with `--update`):
- Forces a single file to be replaced from template regardless of tier or user edits.
- Requires explicit path; cannot combine with `--yes`.
- Prints: `[forced] <rel>` after applying.

**`--accept --file REL_PATH`**:
- Marks a file as "user version accepted": updates stored template hash in `.mkproj` to current template hash without overwriting disk.
- Effect: file no longer shows as conflict until template changes again.
- Prints: `[accepted] <rel>` on success.

**Verify:**
```bash
bash -n bootstrap.sh
mkproj --update --force-file CLAUDE.md <project>  # replaces CLAUDE.md
mkproj --accept <project> --file .gitignore       # resolves conflict silently
```

---

### Task 9: bootstrap.sh -- `--restore-infra`

**Behaviour:**
- Finds all `skip_deleted_infra` decisions across the project.
- Always interactive: prints each file with what will be restored, asks `[r]estore / [s]kip / [q]uit`.
- No `--yes` override (intentionally always requires confirmation).
- Never touches directive or optional files.

**Verify:**
```bash
bash -n bootstrap.sh
# Delete a hook in test project, run mkproj --restore-infra, verify prompt shown.
```

---

### Task 10: bootstrap.sh -- `--list-tiers`

**Behaviour:**
- Reads `.mkproj` for a project, prints a table: `TIER | STATUS | REL_PATH`.
- Sorted by tier (directive first, then infrastructure, then optional), then by path.
- No writes. Exit 0 always.

**Output example:**
```
TIER            STATUS          FILE
directive       skip_user_edit  CLAUDE.md
directive       skip_user_edit  AGENTS.md
infrastructure  auto_update     .claude/hooks/save-response.sh
infrastructure  skip_unchanged  .claude/settings.json
optional        skip_deleted    docs/database.md
```

**Verify:**
```bash
bash -n bootstrap.sh
mkproj --list-tiers <project> | head -5
```

---

### Task 11: man page update

**Files:**
- Modify: `bootstrap.sh` (the `_usage_text` heredoc)

**Add to SYNOPSIS:**
```
mkproj --check [DIR]
mkproj --safe-update [DIR]
mkproj --report [DIR]
mkproj --restore-infra [DIR]
mkproj --list-tiers [DIR]
mkproj --update [NAME] --force-file REL_PATH
mkproj --accept [NAME] --file REL_PATH
```

**Add to MODES section:** one paragraph per new mode explaining behaviour, tier interactions, and when to use it.

**Add to FILES section:** `templates/.mkproj-manifest.json` entry explaining tiers.

**Verify:**
```bash
mkproj --help | grep -c "safe-update\|check\|report\|restore-infra\|list-tiers\|force-file\|accept"
# expect 7 or more matches
```

---

### Task 12: syntax check and commit

**Verify all files:**
```bash
bash -n bootstrap.sh lib/registry.sh lib/update.sh && echo "all syntax ok"
jq empty templates/.mkproj-manifest.json && echo "manifest valid"
mkproj --version
mkproj --help | head -5
```

**Commit:**
```bash
git add templates/.mkproj-manifest.json lib/registry.sh lib/update.sh bootstrap.sh
git commit -m "feat: add file tier system (directive/infrastructure/optional) with --check, --safe-update, --report, --force-file, --accept, --restore-infra, --list-tiers"
```

---

## Review gates before marking complete

- [ ] `bash -n` passes on all three modified shell files
- [ ] Manifest JSON validates with `jq empty`
- [ ] Every template file in `templates/` has a manifest entry or is covered by `default_tier`
- [ ] `--check` exits 2 on directive deletion, 1 on infra warning, 0 when clean
- [ ] `--safe-update` does NOT modify CLAUDE.md or AGENTS.md under any circumstances
- [ ] `--report` produces valid Markdown with correct fix commands
- [ ] `--restore-infra` refuses `--yes` override
- [ ] `--list-tiers` output is sorted and human-readable
- [ ] `--help` documents all 7 new flags/modes
- [ ] No regressions: existing `--update`, `--scan`, `--status`, `--pending`, `--adopt` behaviour unchanged
