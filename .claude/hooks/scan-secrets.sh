#!/bin/bash
# Scans file content for accidental secrets before writing.
# Used as a PreToolUse hook for Edit|Write operations.
# Exit 2 = block. Exit 0 = allow.

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip session archives and responses directory -- Claude writes these and they never contain secrets.
case "$FILE_PATH" in
  */responses/*) exit 0 ;;
esac

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [ "$TOOL_NAME" = "Write" ]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
elif [ "$TOOL_NAME" = "Edit" ]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
else
  exit 0
fi

if [ -z "$CONTENT" ]; then
  exit 0
fi

MATCHES=""

if echo "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  MATCHES="$MATCHES AWS access key (AKIA...);"
fi

if echo "$CONTENT" | grep -qiE '(aws_secret_access_key|secret_key)[[:space:]]*[=:][[:space:]]*["'"'"'"]?[A-Za-z0-9/+=]{40}'; then
  MATCHES="$MATCHES AWS secret key;"
fi

if echo "$CONTENT" | grep -qE '(ghp_|gho_|ghs_|ghr_|github_pat_)[a-zA-Z0-9_]{20,}'; then
  MATCHES="$MATCHES GitHub token;"
fi

if echo "$CONTENT" | grep -qE 'sk-[a-zA-Z0-9-]{20,}'; then
  MATCHES="$MATCHES API key (sk-...);"
fi

if echo "$CONTENT" | grep -qE 'xox[bpras]-[0-9a-zA-Z-]{10,}'; then
  MATCHES="$MATCHES Slack token;"
fi


IDENT_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/private-identifiers.txt"
if [ -f "$IDENT_FILE" ]; then
  IDENT_PATTERNS=$(grep -vE '^[[:space:]]*(#|$)' "$IDENT_FILE" | paste -sd'|' -)
  if [ -n "$IDENT_PATTERNS" ] && echo "$CONTENT" | grep -qE "$IDENT_PATTERNS"; then
    MATCHES="$MATCHES personal identifier;"
  fi
fi

if echo "$CONTENT" | grep -qE -- '-----BEGIN[[:space:]]+(RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'; then
  MATCHES="$MATCHES private key block;"
fi

if echo "$CONTENT" | grep -qE '(mongodb|postgres|mysql|redis|amqp|smtp)(\+[a-z]+)?://[^:[:space:]]+:[^@[:space:]]+@'; then
  MATCHES="$MATCHES connection string with credentials;"
fi

if echo "$CONTENT" | grep -qiE '(password|secret|token|api_key|apikey|api_secret)[[:space:]]*[=:][[:space:]]*["'"'"'"][^"'"'"'"]{8,}["'"'"'"]' && \
   ! echo "$CONTENT" | grep -qiE '(password|secret|token|api_key|apikey|api_secret)[[:space:]]*[=:][[:space:]]*["'"'"'"]?(process\.env|os\.environ|getenv|\$\{|ENV\[|env\()'; then
  MATCHES="$MATCHES hardcoded credential;"
fi

if [ -n "$MATCHES" ]; then
  REASON="Possible secret detected in content:$MATCHES Review carefully before allowing."
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"$REASON\"}}"
  # exit 0 so the JSON "ask" decision drives a prompt. exit 2 would hard-block
  # regardless of the JSON, which was the pre-fix behavior of this file.
  exit 0
fi

exit 0
