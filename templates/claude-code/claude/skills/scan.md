# /scan -- Privacy and secrets scan

Scan the project's tracked files for personal identifiers, secrets, and exposure risks.

## Run these checks in order

**1. Absolute paths**
Search all tracked files for `/home/`, `/Users/`, `/root/`, or any other filesystem root that could identify the developer's machine or username.

```bash
git ls-files | xargs grep -rn "\(/home/\|/Users/\|/root/\)" 2>/dev/null | grep -v "\.example$"
```

**2. Personal names and usernames**
Search for the current system username and any other tokens that look like personal identifiers (short lowercase words appearing in paths or config values, not in code logic).

```bash
git ls-files | xargs grep -rn "\b$(whoami)\b" 2>/dev/null | grep -v "pattern\|patch\|path\|compat\|template\|deprecated"
```

**3. API keys and secrets**
Search for credential patterns. Flag any match that looks like a real value (not a placeholder like `YOUR_KEY_HERE` or `<token>`).

```bash
git ls-files | xargs grep -rEn "(api[_-]?key\s*=\s*['\"][^'\"]{10,}|secret\s*=\s*['\"][^'\"]{10,}|password\s*=\s*['\"][^'\"]{6,}|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32,}|AKIA[A-Z0-9]{16})" 2>/dev/null | grep -v "\.example$" | grep -v "scan-secrets"
```

**4. Files that should be gitignored but aren't**
Check whether any tracked files match patterns that `.gitignore` should cover.

```bash
git ls-files | grep -E "\.(env|pem|key|p12|pfx)$|^\.env(\.|$)"
git ls-files | grep -E "responses/|backups/|secrets/" | grep -v "\.gitkeep$"
```

**5. Email addresses**
Search for `@` patterns that look like real email addresses (not example.com placeholders).

```bash
git ls-files | xargs grep -rEn "[a-zA-Z0-9._%+]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" 2>/dev/null | grep -v "example\.com\|your@\|user@\|name@\|noreply@"
```

## Reporting

After running all checks, present findings as a numbered list. For each finding:
- File path and line number
- The matched text (truncated if long)
- Severity: **block** (secrets, real credentials) / **fix** (personal identifiers, absolute paths) / **review** (may be intentional)

If no findings, say so explicitly.

Do not auto-fix anything. Present the list and wait for the user to confirm which items to address.
