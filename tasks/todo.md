# PB active backlog

**Rule**: top of list gets done next. Priority descends down the file. Move finished items to the "Done this session" tail or delete; move deferred items down.

See `docs/gotchas.md` for persistent hazards and `CHANGELOG.md` for shipped history.

---

## P0 — current screw

- [ ] **Phase 1 clean-adopt batch, isolated from v2 managed projects**
  - Build a staging directory (e.g. `~/Projects/_phase1/`) containing only the 17 clean-adopt candidates (symlinks so paths don't actually move).
  - Run `mkproj scan ~/Projects/_phase1` interactively; answer yes on each prompt.
  - Verify each adoption: `.mkproj` file present, `mkproj check` clean.
  - Remove the staging dir.
  - Why isolated: scan on real `~/Projects/` currently crashes on the 9 pre-v3 managed projects (G-009) and silently mis-reports their state (G-006).

## P1 — once Phase 1 clean batch is done

- [ ] **Fix `mkproj scan` sub-invocation on v2.x managed projects** (gotcha G-009)
  - Scan calls into the update path for each managed project; update on a v2.0.0/v2.1.0 manifest reaches `install_claude_tree` (bootstrap.sh:573).
  - Separately, `read_choice` under `set -u` leaves `choice` unset when stdin closes mid-prompt (`lib/update.sh:179`).
  - Fix either requires v2→v3 manifest migration (G-006), or scan should skip pre-v3 manifests with a warning until migration ships.
  - Add regression test: `mkproj scan` on a dir containing both a v2 fixture and a v3 fixture does not crash.

- [ ] **v2→v3 manifest path migration** (gotcha G-006)
  - One-shot script. For each v2-tracked file in each of the 9 managed projects, look up its new path in `templates/claude-code/...`. Rewrite the manifest entry. Drop entries for files no longer in template.
  - Required before any of the 9 pre-v3 managed projects can be meaningfully updated.

- [ ] **Fix `release.sh` silent gh-release-create skip**
  - v3.1.1 release.sh pushed the commit and tag but did not create the GitHub release. Manual `gh release create` recovered. Script needs investigation: either the gh call failed silently or the pipeline before line 81 bailed without an error message.

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

- **Released v3.1.1**: fix scan/check/status/pending/safe-update/report/restore-infra/list-tiers dispatch (G-003)
- Fix hook `ask` / exit-2 bug in `protect-files.sh` and `scan-secrets.sh` (G-001)
- Fix `release.sh` to pass `--repo` and tag before push (G-002)
- Add personal-identifier scan class to `scan-secrets.sh`, with `.example` file and docs
- Add `docs/privacy-and-security.md` and index entry
- Gitignore `.claude/private-identifiers.txt` in repo and template
- Scrub historical `/home/pat/` and old-handle references from CHANGELOG and todo
- Release v3.1.0: command-form syntax, governance doc, save-response scan fix, scan-secrets responses/ skip
- Pre-adoption inventory for 43 CLAUDE.md projects (17 ADOPT, 11 SKIP, 15 REVIEW)
