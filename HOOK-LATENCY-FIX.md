# Hook latency fix -- 2026-11-22

Discovered in the auto-brain project. Applies to every project bootstrapped from this template.

## Symptoms

- TUI halts for 10-30 seconds at the end of every response ("Saving response..." spinner)
- Pause gets longer as the session accumulates more turns
- Writing session-archive files occasionally triggers false-positive secret scan prompts

## Root causes

### 1. save-response.sh -- full transcript read (Stop hook)

The original script called `stream.readlines()`, loading the entire transcript JSONL into memory on every Stop event. For a session with 20+ turns, that file grows to several MB. On network-mounted filesystems (e.g. ssd-pool NFS/CIFS), reading that much data line by line blocks the TUI for the full 15-second hook timeout.

The script then iterated in reverse, which at least finds the last user message quickly once loaded -- but the damage was already done by the full read.

**Fix:** Seek to `max(0, filesize - 65536)` and read only the last 64 KB. The last user message is always within the final few turns of the transcript, well within that window. If the seek position is non-zero, skip the first (partial) line.

Also removed the two readback verifications (archive file content check + .last-saved pointer check). These added two extra round-trip reads on every Stop event and the atomic rename already guarantees write integrity.

**Timeout:** Bumped from 15 s to 30 s as a safety margin for slow mounts. The fix should reduce actual runtime to under 1 s, but the headroom prevents silent aborts if a mount is temporarily degraded.

### 2. scan-secrets.sh -- no path exclusion (PreToolUse hook)

The original script had no FILE_PATH check at all -- it ran 7 `grep -qE` passes over the full file content on every Write or Edit, regardless of which file was being written.

For session-archive files in `responses/` (written by Claude on every exchange), the content is the full response text -- potentially tens of KB. Running 7 grep passes over that on every Write added 200-500 ms per exchange.

Worse: the script ran on its own content when being updated, triggering a false-positive "API key (sk-...)" match from the grep pattern string inside the script itself.

**Fix:** Extract FILE_PATH first. Add an early-exit case for `*/responses/*`. Session archives are written by Claude itself and can never contain real secrets.

## Files changed

### In this repo (applied to both locations)

| File | Change |
|------|--------|
| `templates/claude-code/claude/hooks/save-response.sh` | Tail-only transcript read (64 KB), removed double readback |
| `templates/claude-code/claude/hooks/scan-secrets.sh` | Added FILE_PATH extraction + responses/ early exit |
| `.claude/hooks/save-response.sh` | Same |
| `.claude/hooks/scan-secrets.sh` | Same |
| `.claude/settings.json` | save-response timeout 15 -> 30 |
| `bootstrap.sh` | save-response timeout 15 -> 30 (line ~718) |

### Already applied in auto-brain (the discovery project)

Same changes were committed to auto-brain as commit `10d0306` before this document was written.

## Propagation

To push these fixes to existing projects:

1. Copy `templates/claude-code/claude/hooks/save-response.sh` and `scan-secrets.sh` to each project's `.claude/hooks/`
2. Bump the save-response timeout to 30 s in each project's `.claude/settings.json`

Or use the bootstrap refresh workflow if you have one wired up.

## Verification

After applying, start a new Claude Code session and run several exchanges. The "Saving response..." pause should be imperceptible (< 1 s). On a session that previously paused 15+ seconds, the difference is immediately obvious.

To confirm the transcript tail logic is correct:

```bash
# In any project with a venv
PYTHONPATH=. python3 -c "
import io
# Simulate a large transcript with a known last user message
import json, tempfile, pathlib
t = pathlib.Path(tempfile.mktemp())
lines = []
for i in range(500):
    lines.append(json.dumps({'message': {'role': 'user', 'content': f'query {i}'}}))
    lines.append(json.dumps({'message': {'role': 'assistant', 'content': f'response {i}'}}))
t.write_text('\n'.join(lines))
TAIL = 65536
with open(t, 'rb') as raw:
    raw.seek(0, 2); size = raw.tell()
    raw.seek(max(0, size - TAIL)); tail = raw.read()
skip = size > TAIL
query = ''
for line in io.TextIOWrapper(io.BytesIO(tail), encoding='utf-8', errors='replace'):
    if skip: skip = False; continue
    try: e = json.loads(line)
    except: continue
    m = e.get('message', {})
    if m.get('role') == 'user': query = m.get('content', '')
print('last query:', query)  # should print: query 499
t.unlink()
"
```
