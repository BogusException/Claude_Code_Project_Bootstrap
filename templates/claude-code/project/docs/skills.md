# Skills

Skills are reusable Claude Code behaviors stored in `.claude/skills/`. Invoke them
with a slash command during any Claude Code session.

## Available skills

### /audit

Analyzes the project and proposes a prioritized improvement list.

Run it when you have a working draft and want to catch gaps, inconsistencies,
tech debt, or anything that looks unfinished. It reads the project structure,
recent session archives, and docs, then presents a numbered list. Nothing
changes until you approve specific items by number.

```
/audit         standard pass
/audit deep    also cross-references session history for decisions that drifted
```

Installed at `.claude/skills/audit.md`. Available for the duration of any
session in which it is invoked.

## Adding skills

Drop a `name.md` file into `.claude/skills/` with the skill's instructions.
Claude Code will make it available as `/name` in any session opened in this project.
