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

mkdir -p "$RESPONSES_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
FILE="$RESPONSES_DIR/${TIMESTAMP}.txt"

python3 - "$TRANSCRIPT" "$RESPONSE" "$FILE" <<'PY'
import sys, json, os

transcript_path = sys.argv[1]
response        = sys.argv[2]
out_path        = sys.argv[3]

# ── Extract last user-typed message ──────────────────────────────────────────
query = "(query not captured)"
if os.path.isfile(transcript_path):
    last_text = ""
    with open(transcript_path) as f:
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
            if isinstance(content, str) and content.strip():
                last_text = content.strip()
            elif isinstance(content, list):
                texts = [b["text"] for b in content
                         if isinstance(b, dict)
                         and b.get("type") == "text"
                         and b.get("text", "").strip()]
                if texts:
                    last_text = "\n".join(texts)
    if last_text:
        query = last_text

# ── Strip console-only footer from response ───────────────────────────────────
# Strip console-only footers (always last 2 lines, either format):
#   ---
#   Previous exchange saved: responses/TIMESTAMP.txt
#   --- OR ---
#   Saved to responses/TIMESTAMP.txt via Stop hook.
lines = response.rstrip("\n").split("\n")
if len(lines) >= 2 and lines[-2] == "---" and (
        lines[-1].startswith("Previous exchange saved:")
        or lines[-1].startswith("Saved to responses/")
        or "via Stop hook" in lines[-1]):
    lines = lines[:-2]
clean_response = "\n".join(lines).rstrip()

# ── Write file ────────────────────────────────────────────────────────────────
with open(out_path, "w") as f:
    f.write("=== QUERY ===\n")
    f.write(query + "\n")
    f.write("\n=== RESPONSE ===\n")
    f.write(clean_response + "\n")
PY

printf '%s\n' "$FILE" > "$LAST_SAVED"
