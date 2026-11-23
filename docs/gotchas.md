# PB gotchas

Hard-won surprises worth remembering. One section per gotcha: symptom, cause, workaround or fix, status.

Keep this file alive. Add to it when something burns a session; prune when a fix lands and the hazard is gone.

---

## G-001: Hook "ask" decision silently became "deny"

**Symptom**: Edit/Write calls on `.claude/settings.json`, `.claude/hooks/*`, or files flagged by secret regex got blocked with `"No stderr output"`. No prompt surfaced. Subagents and the main session both hit it.

**Cause**: `protect-files.sh` and `scan-secrets.sh` emitted `"permissionDecision":"ask"` in JSON, then called `exit 2`. In the Claude Code hook protocol, `exit 2` is a hard block regardless of JSON payload. The `ask` decision requires `exit 0` so the JSON drives a prompt. Every `ask` was silently promoted to `deny`.

**Fix**: `ae4256d`. `emit()` now exits 0 on `ask`, 2 on `deny`. Both live hooks and templates patched.

**Status**: fixed in v3.1.0 post-release. Regression test still needed in `mkproj test`.

---

## G-002: `release.sh` assumed origin fetch URL was a GitHub host

**Symptom**: Running `release.sh` pushed commits but did NOT publish the GitHub release. `release.sh` output ended at the push without printing "Released vX.Y.Z successfully." `gh release view` returned "none of the git remotes configured for this repository point to a known GitHub host."

**Cause**: Origin has split fetch/push URLs. Fetch URL is a local bare path (`/home/pat/Repositories/project-bootstrap.git`). `gh` auto-detects the repo from the fetch URL, sees a local path, refuses. Compounding issue: `~/.config/gh/hosts.yml` token was invalid, but `GITHUB_TOKEN` env var was valid; status showed the split-brain.

**Fix**: `ae4256d`. `release.sh` now derives `OWNER/NAME` from the first github.com push URL and passes `--repo` to `gh release create`. Also creates the local annotated tag before `git push --follow-tags`.

**Status**: fixed.

---

## G-003: Maintenance commands broken in v3.1.0 (scan/check/status/pending/safe-update/report/restore-infra/list-tiers)

**Symptom**: `mkproj scan <DIR>` dies at `parse_args` (bootstrap.sh:324, exit 1). `mkproj scan` from inside a project dies at bootstrap.sh:394 with `PROJECT_NAME: unbound variable`. Legacy `--scan` form identical. Same for the other seven maintenance modes.

**Cause**: Two bugs. (1) `lib/input.sh:169` used `[[ -z "$SCAN_DIR" ]] && SCAN_DIR="$PWD"` as the last line of `parse_args`. When a DIR arg was given, the test was false, the `&&` returned non-zero, which under `set -e` aborted bootstrap at line 324. (2) `main()` ran `phase1_preflight` before the mode dispatch at lines 1379-1389. The early-return in `initialize()` worked but it skipped the code that sets `PROJECT_NAME`, so preflight read an unset variable under `set -u`.

**Fix**: v3.1.1. Converted the `&&` to an `if` block. Moved all 8 maintenance modes out of `main()`'s case and into the top-level case at `bootstrap.sh:1420`, so they dispatch BEFORE `main()` is called. Only `update`, `accept`, and `adopt` stay in main.

**Status**: fixed.

---

## G-004: `.mkproj` is a file, not a directory

**Symptom**: `find ~/Projects -maxdepth 2 -name ".mkproj" -type d` returns zero, suggesting no projects are managed. Wrong conclusion.

**Cause**: `.mkproj` is a JSON file in the project root, not a directory. `-type d` excludes it.

**Fix**: Always use `-type f` (or omit `-type`) when enumerating managed projects.

**Status**: documentation, no code change needed.

---

## G-005: Projects can carry both CLAUDE.md and AGENTS.md

**Symptom**: Older PB-scaffolded projects have both `CLAUDE.md` and `AGENTS.md`. Only one is actually the project's directive file; the other is a vestigial template default.

**Cause**: Pre-agent-choice PB installed both files unconditionally because it didn't know which agent the user wanted. Later versions added an interactive agent-choice prompt but DID NOT filter the template install to match (see TODO-D).

**Detection rule**: CRC32 each file against the current template default (`templates/claude-code/project/{CLAUDE,AGENTS}.md`). File whose CRC matches template default is vestigial. File whose CRC does NOT match is the real directive file.

**Edge case**: BOTH files default-CRC → agent identity undecidable from files alone. Short-term policy (TODO-C) is to overwrite both with latest template defaults.

**Status**: detection works today. Install-time filter is pending (TODO-D). Overwrite-defaults policy is pending (TODO-C).

---

## G-006: v3 silently skips most v2-manifest files due to path refactor

**Symptom**: `mkproj check --verbose` on a v2.0.0 project (pfsense_wazuh) reports ONE file (`.claude/settings.json`) as ok. The v2 manifest tracked more (rules, requirements.txt, etc.). `mkproj status` reports "up to date" despite the v2→v3 architectural gap.

**Cause**: Not a schema-field issue (manifests are parseable). The v3.0.0 multi-template refactor moved tracked files from flat `templates/` to `templates/claude-code/{project,claude,git-hooks}/`. A v2 manifest's recorded paths (e.g. `.claude/rules/database.md`) do not match the file set in v3's template manifest, so v3's check loop silently ignores them.

**Impact**: The 9 pre-v3 managed projects (auto-brain, cc-accelo, claude-skill-goal, claude_skills, cx-goldmine, cx-todolist, model_router, ollama, pfsense_wazuh) appear "up to date" but are actually unmigrated. `update` won't bring them forward.

**Fix (future)**: Write a one-shot v2→v3 manifest migration. For each v2-tracked file, locate its new path in the current template tree (if it still exists) and rewrite the manifest entry. Drop entries for files that no longer exist in the template.

**Workaround**: For Phase 1 batch work, run scan only against directories that exclude the 9 managed projects. The 17 clean-adopt candidates are listed in `responses/internal/phase1-inventory.md` section 2.

**Status**: open. Blocks the resolution of the 9 pre-v3 managed projects.

---

## G-007: `tasks/todo.md` had drifted into a historical release log

**Symptom**: `tasks/todo.md` contained the finished v3.0.0 release checklist, not current work. Easy to misread as live backlog.

**Fix**: `tasks/todo.md` is now a priority-sorted live backlog. Historical release logs move to CHANGELOG where they belong.

**Status**: done.

---

## G-009: `mkproj scan` sub-invocation hits template-install code on v2.x managed projects

**Symptom**: Running `mkproj scan ~/Projects` prints two `mkproj failed in phase initialize (line 573, exit 1)` errors before the first project walk, then stdin-reads for interactive prompts fail with `choice: unbound variable` under set -u.

**Cause (hypothesized)**: scan's inner loop tries to `update` each managed project. For v2.0.0/v2.1.0 manifests (the 9 pre-v3 projects: auto-brain, cc-accelo, claude-skill-goal, claude_skills, cx-goldmine, cx-todolist, model_router, ollama, pfsense_wazuh), the update path reaches `install_claude_tree` at bootstrap.sh:573 which is a bootstrap-time template walker, not an update-time one. Separately, `read_choice` under set -u leaves `choice` unset if stdin closes mid-prompt.

**Workaround for Phase 1 clean-adopt batch**: run scan on a directory that excludes the 9 pre-v3 projects. The 17 clean-adopt candidates are in `responses/internal/phase1-inventory.md` section 2.

**Status**: open. Needs its own screw. Captured in tasks/todo.md. Symlink-follow issue in `scan_projects` fixed in v3.1.3 (separate from the v2.x crash — that remains open).

---

## G-010: `mkproj adopt` refused projects with real history in v3.1.0 / v3.1.1

**Symptom**: `mkproj adopt` on an existing project with commits died with "STOP: project contains real project commits" at bootstrap.sh:410.

**Cause**: Adopt went through `main()` → `phase1_preflight()` → `check_project_repo()`, which refuses projects with more than 1 commit or whose single commit isn't "Initial project scaffold." That check is correct for bootstrap mode (don't scaffold over an existing project), but the entire purpose of `adopt` is to enroll a project that already has history.

**Fix**: v3.1.2. Moved `adopt` to the top-level dispatcher alongside the maintenance modes. `PROJECT_DIR` is already set by `initialize()` (lines 345-364 handle `adopt`, `accept`, `update`), so the top-level case can call `run_adopt_mode` directly.

**Status**: fixed.

---

## G-011: `mkproj adopt` force-installed stale-path AGENTS.md

**Symptom**: `mkproj adopt` on a project that lacked `AGENTS.md` died with `cp: cannot stat '/ssd-pool/.../templates/AGENTS.md': No such file or directory`. Even when it would have succeeded (on machines where the old flat `templates/` tree was still present), it would have force-installed Codex's directive file into a project that had explicitly chosen Claude Code only.

**Cause**: `lib/update.sh:608-612` used `$TEMPLATES_DIR/AGENTS.md`, the pre-v3.0 flat template layout. v3.0.0's multi-template refactor moved all project files to `$TEMPLATES_DIR/claude-code/project/`. The code was never updated. Compounding problem: the install was unconditional, ignoring the project's agent choice.

**Fix**: v3.1.2. Rewrote `adopt_project()` to record whichever of `CLAUDE.md` / `AGENTS.md` already exist in the project, hashed against the current template default. Do NOT install new files during adopt. A project with only CLAUDE.md stays Claude-Code-only; a project with both files records both.

**Status**: fixed. Related to TODO-D (install-time agent-choice filter) and TODO-B (dual-MD cleanup).

---

## G-008: `~/Projects/` contains loose files that aren't projects

**Symptom**: `~/Projects/` has 18 top-level files (`.sh`, `.md`, `.ps1`, `.txt`, `.json`, `.html`, `.conf`) plus archive and scratch directories. `mkproj scan ~/Projects` walks past all of them.

**Specific hazard**: `mariaWireguardKeys.txt` sat at top level and almost certainly held credentials. Moved out by user on 2026-11-22.

**Mitigation**: before any batch scan, audit top-level files in `~/Projects/` for credentials. Not a code change; operational procedure.

**Status**: operational.

---

## G-012: Claude Code does not export `CLAUDE_MODEL` to hook subprocesses

**Symptom**: A `UserPromptSubmit` hook that tries to read the active model (to warn when task complexity doesn't match the selected tier) always sees the model from session start. If the user runs `/model sonnet` mid-session, the hook still reports the original model.

**Cause**: Claude Code does not inject a `CLAUDE_MODEL` environment variable when it invokes hook subprocesses. Hooks launch in a subprocess with no session state from the harness. The hook has no way to discover that the model changed.

**Impact**: Any hook-based model-matching or cost-warning logic is unreliable after a mid-session model switch. For project-bootstrap specifically this means the `auto-brain-warn` hook (which advises on model selection) cannot be built reliably as a `UserPromptSubmit` hook.

**Workaround**: Use a Claude Code **mod** instead of a hook. Mods run in-process and have direct access to `$.session.model()`, which always reflects the current model. The `auto-brain-warn` mod in `~/.claude/smartmodel/mods/` demonstrates this pattern.

**Bug filed**: anthropics/claude-code#111757.

**Status**: open upstream. Workaround via mod is functional.
