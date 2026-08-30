#!/usr/bin/env bash
# Saves the last user query + Claude's response to responses/YYYYMMDD-HHMMSS.txt
# Wired as a Stop hook. Input JSON has:
#   last_assistant_message  plain string -- the response text
#   transcript_path         path to JSONL with full conversation

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then exit 0; fi

PROJ="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RESPONSES_DIR="$PROJ/responses"
LAST_SAVED="$PROJ/responses/.last-saved"

INPUT=$(cat)

RESPONSE=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)
[ -z "$RESPONSE" ] && exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

QUERY=""
if [ -f "$TRANSCRIPT" ]; then
  QUERY=$(python3 - "$TRANSCRIPT" <<'PY'
import sys, json

path = sys.argv[1]
last_text = ""
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except Exception:
            continue
        msg = entry.get("message", {})
        if msg.get("role") != "user":
            continue
        content = msg.get("content", "")
        # User-typed messages have content as a plain string
        if isinstance(content, str) and content.strip():
            last_text = content.strip()
        # Some user messages are lists of blocks (tool results, etc.)
        elif isinstance(content, list):
            texts = [b["text"] for b in content
                     if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip()]
            if texts:
                last_text = "\n".join(texts)
print(last_text)
PY
  )
fi

mkdir -p "$RESPONSES_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
FILE="$RESPONSES_DIR/${TIMESTAMP}.txt"

{
  printf '=== QUERY ===\n'
  if [ -n "$QUERY" ]; then
    printf '%s\n' "$QUERY"
  else
    printf '(query not captured)\n'
  fi
  printf '\n=== RESPONSE ===\n'
  printf '%s\n' "$RESPONSE"
} > "$FILE"

# Record filename so next response can confirm it
printf '%s\n' "$FILE" > "$LAST_SAVED"
