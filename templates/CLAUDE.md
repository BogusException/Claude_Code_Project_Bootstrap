# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Response format (required on every response -- no exceptions)

**Line 1:** A single ✓ character. This is a health check -- when the user stops seeing ✓, Claude Code has lost its instruction context.

**Last lines of every response:** Read `responses/.last-saved` and end with:

```
---
Previous exchange saved: responses/20260828-214500.txt
```

If `responses/.last-saved` does not exist or is empty, write `Previous exchange saved: (none yet)`. This is real disk confirmation -- the `save-response.sh` Stop hook writes the file after each exchange. If the filename stops changing between responses, the hook has stopped firing.

The `save-response.sh` Stop hook writes each exchange to `responses/YYYYMMDD-HHMMSS.txt` after the response completes. The file contains only the human-readable query and response -- no tool output:

```
=== QUERY ===
<the user's message>

=== RESPONSE ===
<Claude's response>
```

`responses/` is git-ignored (content only -- the dir is tracked via `.gitkeep`). Never commit response files.

## Behaviour directives (required)

**Proactive:** When asking a question or presenting options, include a recommendation with brief reasoning. Do not wait to be asked which option is better. You are the expert -- act like it.

**Suggestions:** If a better approach exists, say so in one line before proceeding. Do not implement it without a yes.

## Commands

### Install dependencies (venv must be active)

```bash
source .venv/bin/activate
pip install -r requirements.txt
```

### git changes to filesystem

At the end of every response where any file was added, changed, or deleted:

```bash
git add <the specific changed files>
git commit -m "clear, descriptive message"
git push origin main
```

The `auto-commit.sh` Stop hook is a safety net only. Claude must commit explicitly with a useful message. Never skip the push.

### Asking questions

Whenever you ask a question, suggest your recommendation(s).
You are the expert here, not the user, so be helpful, and don't wait to be asked.
