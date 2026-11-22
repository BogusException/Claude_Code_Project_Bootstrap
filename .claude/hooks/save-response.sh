#!/usr/bin/env bash
set -euo pipefail
PROJ="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PYTHON="$PROJ/.venv/bin/python"
[[ -x "$PYTHON" ]] || { echo "Cannot archive exchange: project .venv interpreter missing." >&2; exit 1; }
exec "$PYTHON" -c '
import datetime,io,json,os,pathlib,sys,tempfile
project=pathlib.Path(sys.argv[1])
payload=json.load(sys.stdin)
response=payload.get("last_assistant_message","")
if not isinstance(response,str):
    raise ValueError("Assistant response is not text")
if not response.strip():
    sys.exit(0)
query=payload.get("prompt","")
transcript=payload.get("transcript_path","")
if transcript:
    # Scan backward through JSONL chunks to find the most recent non-empty user message.
    # Stops as soon as one is found so long transcripts stay fast.
    CHUNK=65536
    buf=b""
    with open(transcript,"rb") as raw:
        raw.seek(0,2); size=raw.tell(); pos=size
        while pos>0 and not query:
            read_size=min(CHUNK,pos); pos-=read_size
            raw.seek(pos); chunk=raw.read(read_size)
            buf=chunk+buf
            lines=buf.split(b"\n")
            buf=lines[0] if pos>0 else b""
            lines=lines[1:] if pos>0 else lines
            for line in reversed(lines):
                line=line.strip()
                if not line: continue
                try: entry=json.loads(line)
                except json.JSONDecodeError: continue
                msg=entry.get("message",{})
                if msg.get("role")!="user": continue
                c=msg.get("content","")
                if isinstance(c,str) and c.strip():
                    query=c.strip(); break
                elif isinstance(c,list):
                    texts=[b["text"] for b in c if isinstance(b,dict) and b.get("type")=="text" and isinstance(b.get("text"),str) and b["text"].strip()]
                    if texts: query="\n".join(texts); break
if not isinstance(query,str) or not query.strip():
    sys.exit(0)  # no query found; skip archive silently
directory=project/"responses"
if directory.is_symlink():
    raise RuntimeError("Refusing a symlinked archive directory")
directory.mkdir(mode=0o700,exist_ok=True)
pointer=directory/".last-saved"
if pointer.is_symlink():
    raise RuntimeError("Refusing a symlinked archive pointer")
body="=== QUERY ===\n"+query+"\n\n=== RESPONSE ===\n"+response.rstrip("\n")+"\n"
if pointer.is_file():
    old=pathlib.Path(pointer.read_text(encoding="utf-8").strip())
    if old.parent.resolve()==directory.resolve() and old.is_file() and old.read_text(encoding="utf-8")==body:
        sys.exit(0)
now=datetime.datetime.now()
for seconds in range(86400):
    path=directory/((now+datetime.timedelta(seconds=seconds)).strftime("%Y%m%d-%H%M%S")+".txt")
    try: descriptor=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    except FileExistsError: continue
    with os.fdopen(descriptor,"w",encoding="utf-8") as stream:
        stream.write(body)
    break
else:
    raise RuntimeError("No unused archive timestamp available")
with tempfile.NamedTemporaryFile(mode="w",encoding="utf-8",dir=directory,prefix=".last-saved-",delete=False) as stream:
    stream.write(str(path)+"\n")
    temporary=stream.name
os.replace(temporary,pointer)
' "$PROJ"
