# PB active backlog

**Rule**: top of list gets done next. Priority descends down the file. Move finished items to the "Done this session" tail or delete; move deferred items down.

See `docs/gotchas.md` for persistent hazards and `CHANGELOG.md` for shipped history.

---

## P0 — current screw

- [ ] **Patch v3.1.1 to fix `scan`/`check`/`update` dispatch** (gotcha G-003)
  - Pinpoint the defect in `lib/input.sh` `parse_args()` or in the `initialize()` early-return at `bootstrap.sh:326-329`.
  - Fix so `MODE=scan|check|update|pending|status|report|safe-update|restore-infra|list-tiers` all return from initialize before bootstrap preflight.
  - Add regression test in `bootstrap.sh test` that calls each maintenance mode against a fresh test-mode project and asserts it does NOT hit bootstrap preflight.
  - Bump to v3.1.1, CHANGELOG entry, release.sh.

## P1 — next screw after v3.1.1 ships

- [ ] **Dry-run `mkproj check ~/Projects/pfsense_wazuh` with v3.1.1**
  - Confirms whether v2.0.0 manifests are accepted (gotcha G-006).
  - If accepted: proceed to P2.
  - If rejected: schema-compat fix becomes its own screw (v3.1.2).

- [ ] **Phase 1 clean-adopt batch: 17 projects**
  - Inventory list in `responses/internal/phase1-inventory.md` section 2 "ADOPT, no extra flags."
  - Projects: ai-models, ai-writer, block_lg_telemetry, books-yumi, brick2, fb-saved, gmail_incremental, grafana-1, isitai, making-money_v1, mempalace_notes, mktg_1, ping-watch, project-bootstrap, rp, selling-digital, syncro.
  - Run `mkproj scan ~/Projects` interactively, answer yes on these only.

## P2 — screws after Phase 1 clean batch

- [ ] **TODO-C: Short-term "overwrite template defaults" policy** (prereq for TODO-B / TODO-D)
  - When `scan`/`update` encounters a file whose on-disk CRC matches an older template default, overwrite silently with current default.
  - Requires historical-default CRC table in `.mkproj-manifest.json` keyed by version.
  - Unblocks safe handling of projects with vestigial `AGENTS.md` or `CLAUDE.md`.

- [ ] **Resolve the 9 pre-v3 managed projects**
  - auto-brain, cc-accelo, claude-skill-goal, claude_skills, cx-goldmine, cx-todolist, model_router, ollama, pfsense_wazuh.
  - Needs v2→v3 manifest migration (gotcha G-006) and TODO-C overwrite policy.

- [ ] **Phase 1 REVIEW group: 15 projects**
  - Hand-review each per `phase1-inventory.md` section 3.

## P3 — architectural work

- [ ] **TODO-D: Install-time agent-choice filter**
  - PB's agent-choice prompt (`claude|codex|none`) must gate which directive files, hooks, and rules install.
  - Persist choice in `.mkproj` as `"agent": "claude"|"codex"`.
  - On adoption, prompt if not set.

- [ ] **TODO-B: Dual-MD cleanup after TODO-C + TODO-D ship**
  - Sweep existing projects. Where only one of CLAUDE.md / AGENTS.md is non-default, delete the other. Where both are default, use the persisted `agent` field from `.mkproj`.

- [ ] **TODO-A: Folder prefix rename pass**
  - `cc-` for Claude Code, `cx-` for Codex, no prefix for other.
  - Script walks `~/Projects/`, proposes renames, updates venv paths and anything hardcoded to the old folder name.
  - Interactive confirmation per rename.

- [ ] **TODO-E: Unused template-file reaper**
  - After >=60 days since install, for optional-tier files whose on-disk CRC still equals template default AND no tracked file references them, offer removal.
  - Command: `mkproj reap` or `mkproj scan --reap`.

## P4 — maintenance and polish

- [ ] **Phase 2: adopt non-Claude git projects** (17 candidates in `phase1-inventory.md` section 4)
  - Run `mkproj adopt --no-global` per project, interactive.

- [ ] **`mkproj diagnose` full hook-execution diagnostic**
  - Enumerate all hooks in `~/.claude/settings.json`, run each with hard timeout, report exit/duration/attribution. claude-mem bun is proof-of-concept.

- [ ] **Move hardcoded hook timeouts into a config file**
  - Per-system tuning.

- [ ] **CI precommit: privacy sweep**
  - GitHub Actions workflow that runs the planned `mkproj scan --privacy` on PRs. Depends on the privacy-scan feature below.

- [ ] **`mkproj scan --privacy`** (spec in `responses/internal/HANDOFF.md` deferred section)
  - Read-only pass that greps every tracked file across every managed project for patterns in `.claude/private-identifiers.txt`.
  - Target release v3.2.0.

## Done this session (2026-11-22, newest first)

- Fix hook `ask` / exit-2 bug in `protect-files.sh` and `scan-secrets.sh` (G-001)
- Fix `release.sh` to pass `--repo` and tag before push (G-002)
- Add personal-identifier scan class to `scan-secrets.sh`, with `.example` file and docs
- Add `docs/privacy-and-security.md` and index entry
- Gitignore `.claude/private-identifiers.txt` in repo and template
- Scrub historical `/home/pat/` and old-handle references from CHANGELOG and todo
- Release v3.1.0: command-form syntax, governance doc, save-response scan fix, scan-secrets responses/ skip
- Pre-adoption inventory for 43 CLAUDE.md projects (17 ADOPT, 11 SKIP, 15 REVIEW)
