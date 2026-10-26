#!/usr/bin/env bash
# Safety net: commit only deliberately staged changes; never stage user files.
set -euo pipefail
PROJ="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJ"
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
git remote get-url origin >/dev/null 2>&1 || exit 0
if git diff --cached --quiet; then
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Auto-commit: unstaged files remain; review and stage specific task files explicitly." >&2
    fi
    exit 0
fi
# Run the bundled guard even if native hooks have not yet been installed.
guard="$PROJ/.githooks/pre-commit"
if [[ -f "$guard" ]]; then
    bash "$guard"
else
    echo "Auto-commit refused: private-path Git guard is missing." >&2
    exit 1
fi
git commit -m "auto-commit: explicitly staged changes at session stop ($(date '+%Y-%m-%d %H:%M:%S'))"
branch="$(git branch --show-current)"
[[ -n "$branch" ]] || { echo "Auto-push refused: detached HEAD." >&2; exit 1; }
git push origin "$branch"
