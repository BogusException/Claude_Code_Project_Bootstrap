---
name: audit
description: Analyze this project and produce a prioritized improvement plan. Run when you have a working draft and want to identify gaps, inconsistencies, tech debt, or missing pieces. Presents a numbered list for your approval before changing anything.
---

# /audit skill

## When to use

Run `/audit` when your project has enough substance to evaluate -- working code, some structure established, decisions already made. Not useful on a fresh scaffold.

## What it does

1. Reads project structure, recent session archives, CLAUDE.md, tasks/todo.md, and any docs.
2. Identifies: gaps between intent and implementation, inconsistencies, missing pieces, tech debt, files that look unfinished.
3. Outputs a numbered, prioritized improvement list with one-line reasoning per item.
4. Waits for your selection before changing anything.

## Instructions

When this skill is invoked:

**Step 1 -- Gather context**
- Read CLAUDE.md for project intent and conventions.
- Read tasks/todo.md for known open work.
- Run `find . -not -path './.git/*' -not -path './responses/*' -not -path './.venv/*' -type f | sort` to get the full file tree.
- Read any files that look incomplete, inconsistent, or structurally important.
- Scan the 3 most recent files in responses/session-archive/ (or responses/) for recent decisions and direction.

**Step 2 -- Identify improvements**

Look for:
- Structural gaps: folders or files referenced in docs or CLAUDE.md that don't exist
- Implementation drift: documented behavior that the code doesn't match
- Missing tests for functionality that exists
- Docs that are stubs or placeholders
- TODO/FIXME markers in code
- Inconsistent naming or patterns across files
- Security or privacy issues (secrets in tracked files, missing .gitignore entries)
- Anything that would fail a staff-engineer code review

**Step 3 -- Present the plan**

Output exactly this format:

```
Audit complete. Found N items:

1. [PRIORITY: high/med/low] Short title
   What: one sentence describing the problem
   Fix: one sentence describing the change

2. ...
```

Sort by priority (high first). Be specific -- file paths and line numbers where relevant.

Then ask:
"Which would you like to address? (number, range like 1-3, 'all', or 'none')"

**Step 4 -- Execute approved items only**

For each approved item, make the change, verify it, and check it off. Do not touch unapproved items.

## Modifiers

`/audit deep` -- also cross-references session archive history to catch decisions that were made and then drifted. Slower but more thorough.
