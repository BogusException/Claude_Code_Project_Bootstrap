# PB privacy and security

## Scope

PB ships two layers of pre-write protection:

1. `protect-files.sh` denies Edit/Write on sensitive paths (`.env`, keys,
   certs, lockfiles, `.git/`, `secrets/`) and asks before touching
   `settings.json` or any `.claude/hooks/*` script.
2. `scan-secrets.sh` inspects new file content for known secret patterns
   (AWS, GitHub, OpenAI, Slack, connection strings, hardcoded credentials,
   PEM private key blocks) and asks the user to confirm before writing.

Both hooks are PreToolUse hooks matched on `Edit|Write`. They never run on
`Bash`, so a shell command that writes a file does not trip them. Treat
that as a known gap, not a loophole.

## Personal identifier scanning

`scan-secrets.sh` also checks for per-developer identifiers you want kept
out of commits: your local username in absolute paths, your machine
hostname, an old handle, an email address. The hook reads one regex per
line from:

```
.claude/private-identifiers.txt
```

If the file does not exist, the check is skipped silently. Blank lines and
lines starting with `#` are ignored. Each pattern is passed to `grep -E`
directly, so write it exactly as you would type a regex alternative.

A starter file ships as `.claude/private-identifiers.txt.example`. Copy it,
remove the `#` on the lines you want active, and add your own:

```
# /home/youruser/
# youruser@
# yourhost
# your-old-github-handle
```

The file itself is per-developer and should stay out of git. Add it to
`.gitignore` on projects where you plan to use it; the template keeps the
`.example` tracked and the live file untracked.

## Hook decision protocol

Both hooks emit a JSON `permissionDecision` of `allow`, `ask`, or `deny`
and exit with a code consistent with that decision. In the Claude Code
hook protocol, exit 2 is a hard block regardless of the JSON payload, so
an `ask` decision must exit 0 for the prompt to surface. Earlier versions
of these hooks exited 2 for both `ask` and `deny`, which silently promoted
every `ask` to a hard block. Fixed in v3.1.1.
