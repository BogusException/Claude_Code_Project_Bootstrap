# PB lessons

Patterns learned the hard way. Each entry is a trigger I recognize next time and a rule that prevents the mistake.

Append to this file after any correction from the user. Prune only when the lesson is clearly internalized across multiple sessions.

---

## L-001: HANDOFF is for session boundaries, not running notes

**Trigger**: I started appending every finding, TODO, and context dump to `responses/internal/HANDOFF.md` because it was the one file already open. HANDOFF got bloated and unreadable.

**Rule**: HANDOFF.md = pointer to current state for the next session. Short. Running knowledge goes in `docs/gotchas.md`, backlog goes in `tasks/todo.md`, patterns go here. If I catch myself about to append anything but a session-boundary pointer to HANDOFF, redirect to the right file.

---

## L-002: One screw at a time, finish before branching

**Trigger**: In the middle of Phase 1 inventory I surfaced TODO-A through TODO-E as new branches, then discovered v3.1.0 was broken (G-003), then kept offering decision trees about which direction next. The user got lost and tired.

**Rule**: Keep exactly ONE screw active. Finish it (ship, test, close) before starting the next. New findings go to `tasks/todo.md` as items for future screws, not as decision prompts. Decision prompts are for the end of a screw, not the middle.

---

## L-003: Verify dispatch, not just test suite

**Trigger**: `mkproj test` passed 187/187 before the v3.1.0 release. I treated that as proof the release was good. It wasn't — `scan`, `check`, `update` were broken and `test` has its own code path that doesn't exercise them.

**Rule**: Before releasing, exercise EVERY user-facing mode against a fixture, not just `test`. If `test` is the only coverage, add dispatch-smoke tests for the other modes as part of `mkproj test` itself.

---

## L-004: `.mkproj` is a file, not a directory

**Trigger**: I ran `find ... -name .mkproj -type d`, got zero results, told the user the plan's "9 managed projects" was false. It was correct.

**Rule**: When testing a plan's assertion against disk, verify the assertion with a method the plan author would use. For files, use `-type f` or no `-type` at all. For filesystem-truth claims, two independent queries beats one confident query.

---

## L-005: TUI-only communication loses context fast

**Trigger**: I produced long findings sections (the pfsense_wazuh inspection, the gotcha diagnosis) directly into the chat stream. They scrolled away. The user had to ask what state we were in multiple times.

**Rule**: Any finding worth keeping goes into a file FIRST (`docs/gotchas.md`, `tasks/todo.md`, an inventory report in `responses/internal/`). The chat line links to the file, doesn't duplicate its content. The TUI is a notification channel, not a knowledge store.

---

## L-006: Required response format is non-negotiable

**Trigger**: Dropped the `✓ / Confidence / Role / Reframe` header for several turns. Also presented options without a lead recommendation on multiple turns. CLAUDE.md requires both on every response. User had to call it out explicitly.

**Rule**: Every response begins with the four-line header (even one-sentence replies). Every multi-option prompt leads with "I recommend X because Y." A bare "which do you prefer?" is a violation.

---

## L-007: Say "I'm starting" ONLY if I'm actually calling a tool in the same response

**Trigger**: Sent a message that ended "Starting now on step 1." but made no tool calls in that same response. From the user's seat it looked like I had stopped and was waiting on them.

**Rule**: If the message says I'm starting, there must be a tool call in the same response (or the next report must arrive automatically via subagent). Otherwise phrase it as "ready to start — say go" and wait explicitly.
