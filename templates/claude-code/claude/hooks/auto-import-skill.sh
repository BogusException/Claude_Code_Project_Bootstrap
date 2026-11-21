#!/usr/bin/env bash
# Global PostToolUse hook on Skill tool.
# When any skill is invoked from the global ~/.claude/skills/ path and is not
# already present in the current project's .claude/skills/, copies it there
# and logs the import to tasks/skills-manifest.md.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then exit 0; fi

[ -z "${CLAUDE_PROJECT_DIR:-}" ] && exit 0

INPUT=$(cat)
SKILL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
[ -z "$SKILL_NAME" ] && exit 0

LOCAL_DIR="$CLAUDE_PROJECT_DIR/.claude/skills"
GLOBAL_DIR="$HOME/.claude/skills"

BASE_NAME="${SKILL_NAME##*:}"

[ -d "$LOCAL_DIR/$BASE_NAME" ] && exit 0
[ -d "$LOCAL_DIR/$SKILL_NAME" ] && exit 0

SOURCE=""
[ -d "$GLOBAL_DIR/$BASE_NAME" ]   && SOURCE="$GLOBAL_DIR/$BASE_NAME"
[ -z "$SOURCE" ] && [ -d "$GLOBAL_DIR/$SKILL_NAME" ] && SOURCE="$GLOBAL_DIR/$SKILL_NAME"
[ -z "$SOURCE" ] && exit 0

mkdir -p "$LOCAL_DIR"
cp -r "$SOURCE" "$LOCAL_DIR/"

MANIFEST="$CLAUDE_PROJECT_DIR/tasks/skills-manifest.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

if [ ! -f "$MANIFEST" ]; then
    mkdir -p "$(dirname "$MANIFEST")"
    printf '# Skills Manifest\nAuto-generated. Lists all skills used by this project.\nCompare .claude/skills/ against this file before packaging.\n\n| Skill | Source | Date Added | Notes |\n|---|---|---|---|\n' > "$MANIFEST"
fi

echo "| $BASE_NAME | auto-imported | $TIMESTAMP | Invoked in session, copied from global |" >> "$MANIFEST"
echo "Auto-imported skill '$BASE_NAME' into .claude/skills/" >&2
