# CLAUDE.md

This file is the shared source of project directives for Claude Code and Codex.

## Response format (required on every response -- no exceptions)

**Line 1:** A single ✓ character. This is a health check -- when the user stops seeing ✓, Claude Code has lost its instruction context.

**Last lines of every response:** Invoke the Read tool on `responses/.last-saved` -- this is a mandatory tool call, not a knowledge-based answer. End with:

```
---
Previous exchange saved: responses/20260828-214500.txt
```

If the Read tool returns empty content or the file does not exist, write `Previous exchange saved: (none yet)`. Never hardcode `(none yet)` without attempting the Read first. This is real disk confirmation -- the `save-response.sh` Stop hook writes the file after each exchange. If the filename stops changing between responses, the hook has stopped firing.

The `save-response.sh` Stop hook writes each exchange to `responses/YYYYMMDD-HHMMSS.txt` after the response completes. The file contains only the human-readable query and response -- no tool output:

```
=== QUERY ===
<the user's message>

=== RESPONSE ===
<Claude's response>
```

Everything under responses/ is private and git-ignored, including internal documents, exchanges, and screenshots. Never stage, commit, or push anything from this directory, including placeholders.

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

## Configuration backups (required for every agent)

Before editing or replacing any existing configuration or directive file, make a
verified filesystem copy in a backups/ directory beside that file, named
<filename>.YYYYMMDD-HHMMSS-NNNNNNNNN.bak. Preserve the original permissions,
ownership, ACLs, and extended attributes where supported. Keep backup directories
private and excluded from Git. Git is not a backup. If the backup cannot be
created and verified, stop before editing the original.

## Codex-specific behavior

AGENTS.md is only an entry point to this file. Keep all behavioral directives
here; do not maintain a separate copy of these rules for Codex.

Read applicable .claude/rules/*.md and honor each file's path scope. Claude
settings and hooks are not automatically Codex settings or hooks. Use equivalent
available tools for these instructions and report any enforcement you cannot
provide. Do not change Claude Code settings to configure Codex.

For Codex, the following archive procedure replaces the Claude-only Stop-hook
and previous-exchange footer instructions above. Before the final answer, write
the exact user query and final response, without tool output or private reasoning,
to a new responses/YYYYMMDD-HHMMSS.txt. Never overwrite an existing exchange;
choose the next unused second if necessary. Read the file back and verify its
contents, update and read responses/.last-saved, then deliver the saved response.
The first line must be a single checkmark character and the last line must be
the absolute path to that verified current exchange file. If saving fails, report
the failure instead of claiming a successful save.

Inspect Git status and remotes before work. Stage only task-owned, non-private
files; preserve unrelated changes. Follow the explicit commit and push workflow
above, subject to actual tool authorization. If an operation is denied, report
what did not run and obtain the required authorization; do not bypass the denial.
Never create commits solely for ignored exchange archives or backups.

Use the project's .venv interpreter for Python commands, tests, and dependency
installation. Activate it in the same shell invocation, or invoke its interpreter
directly; prefer python -m pip through that interpreter. A Linux venv on a mapped
share must run on its Linux host, not through Windows Python. Do not silently
fall back to a global interpreter. Create a missing project venv before installing
dependencies. Check that the interpreter belongs to this project; do not rely on
a previously activated environment from another directory.

The checkmark and archive path indicate compliance with these instructions.
They do not prove complete context retention or answer correctness.

## Git guard and launch behavior

Native pre-commit and pre-push hooks reject private paths independently of agent
tooling. Do not bypass them. The auto-commit Stop hook never stages files; it
commits only explicitly staged changes and reports commit/push failures.
Global shell/hook configuration is opt-in during bootstrap. Choose Claude,
Codex, or no launch; each agent keeps its own model/status settings.

## Command execution

Never print the process environment or enable shell tracing while sourcing user
configuration. From a different host shell, pass remote programs structured
arguments through subprocess APIs rather than mixing nested shell quote rules.
