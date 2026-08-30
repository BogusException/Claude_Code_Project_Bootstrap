#!/usr/bin/env bash
# Safety-net auto-commit: if Claude left uncommitted changes at end of response,
# stages and commits them with a timestamped message, then pushes.
# Wired as a Stop hook -- fires after every Claude response.
# Claude should commit explicitly with a descriptive message; this catches misses.

set -uo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJ" || exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Do not auto-commit if no remote is configured -- accumulating commits
# in a remote-less repo makes it impossible to re-run bootstrap to finish setup.
git remote get-url origin >/dev/null 2>&1 || exit 0

if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
  exit 0
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
git add -A
git commit -m "auto-commit: uncommitted changes at session stop ($TIMESTAMP)" --no-gpg-sign 2>/dev/null || exit 0
git push origin "$(git branch --show-current)" 2>/dev/null || true
