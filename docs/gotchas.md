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

## G-003: `mkproj scan`, `check`, `update` broken in v3.1.0

**Symptom**: `mkproj scan <DIR>` dies at `parse_args` (bootstrap.sh:324, exit 1). `mkproj scan` from inside a project dies at bootstrap.sh:394 with `PROJECT_NAME: unbound variable`. Legacy `--scan` form identical. `check` same pattern.

**Cause (under investigation)**: `initialize()` has an early-return branch at line 326-329 that should exit for `MODE=scan|check|update|...`. It isn't firing. Either `parse_args` fails before `MODE` gets set, or `MODE` is set to something other than the expected value. `mkproj test` works because test mode has its own branch.

**Workaround**: none. These are the primary maintenance commands.

**Status**: open. Target v3.1.1 patch. Blocks the Phase 1 project-adoption rollout.

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

## G-006: v3.1.0 maintenance commands may not accept v2.x manifests

**Symptom**: `mkproj check` on a v2.0.0-manifest project (pfsense_wazuh) may or may not work once G-003 is fixed. Testing blocked behind G-003.

**Cause (hypothesized)**: Manifest schema may have changed between v2 and v3 (multi-template rewrite). `lib/update.sh` may expect v3 fields that v2 manifests lack.

**Status**: unknown. Will be verifiable once G-003 is patched. Dry-run on pfsense_wazuh is the canary (smallest + oldest-schema among the 9 pre-v3 managed projects).

---

## G-007: `tasks/todo.md` had drifted into a historical release log

**Symptom**: `tasks/todo.md` contained the finished v3.0.0 release checklist, not current work. Easy to misread as live backlog.

**Fix**: `tasks/todo.md` is now a priority-sorted live backlog. Historical release logs move to CHANGELOG where they belong.

**Status**: done.

---

## G-008: `~/Projects/` contains loose files that aren't projects

**Symptom**: `~/Projects/` has 18 top-level files (`.sh`, `.md`, `.ps1`, `.txt`, `.json`, `.html`, `.conf`) plus archive and scratch directories. `mkproj scan ~/Projects` walks past all of them.

**Specific hazard**: `mariaWireguardKeys.txt` sat at top level and almost certainly held credentials. Moved out by user on 2026-11-22.

**Mitigation**: before any batch scan, audit top-level files in `~/Projects/` for credentials. Not a code change; operational procedure.

**Status**: operational.
