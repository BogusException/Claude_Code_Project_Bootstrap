#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Read version from source
VERSION="$(grep '^MKPROJ_VERSION=' bootstrap.sh | cut -d'"' -f2)"
if [[ -z "$VERSION" ]]; then
    echo "ERROR: could not read MKPROJ_VERSION from bootstrap.sh" >&2
    exit 1
fi
TAG="v${VERSION}"
echo "Releasing $TAG"

# Verify tag does not already exist
if git tag | grep -qx "$TAG"; then
    echo "ERROR: tag $TAG already exists. Bump MKPROJ_VERSION before releasing." >&2
    exit 1
fi

# Verify CHANGELOG has a section for this version
if ! grep -q "## \[$VERSION\]" CHANGELOG.md; then
    echo "ERROR: CHANGELOG.md has no section for [$VERSION]." >&2
    exit 1
fi

# Derive OWNER/NAME from the first github.com push URL. The fetch URL may be a
# local bare path, so only the push URLs are checked.
REPO_SLUG=""
while IFS= read -r remote_url; do
    if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
        REPO_SLUG="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
        break
    fi
done < <(git remote get-url --all --push origin)
if [[ -z "$REPO_SLUG" ]]; then
    echo "ERROR: origin has no github.com push URL. Cannot create GitHub release." >&2
    exit 1
fi

# Run tests
echo "Running test suite..."
bash bootstrap.sh --test
echo "Tests passed."

# Syntax check
bash -n bootstrap.sh
for f in lib/*.sh; do bash -n "$f"; done
echo "Syntax check passed."

# Compute CRC32 of bootstrap.sh
if command -v crc32 &>/dev/null; then
    CRC="$(crc32 bootstrap.sh)"
elif command -v python3 &>/dev/null; then
    CRC="$(python3 -c "import binascii,sys; data=open('bootstrap.sh','rb').read(); print(format(binascii.crc32(data)&0xffffffff,'08x'))")"
else
    echo "WARNING: no crc32 or python3 found, skipping CRC stamp" >&2
    CRC="(unavailable)"
fi

# Stamp CRC into CHANGELOG under this version's header
sed -i "s|## \[$VERSION\] - \(.*\)$|## [$VERSION] - \1 -- CRC32(bootstrap.sh) \`$CRC\`|" CHANGELOG.md
echo "CRC stamped: $CRC"

# Commit
git add CHANGELOG.md tasks/todo.md bootstrap.sh lib/ templates/ docs/ RELEASING.md release.sh 2>/dev/null || true
git diff --cached --quiet && { echo "Nothing staged to commit."; } || \
    git commit -m "Release $TAG"

# Tag the new HEAD so --follow-tags pushes it with the commit
if [[ -z "$(git tag --list "$TAG")" ]]; then
    git tag -a "$TAG" -m "Release $TAG"
fi

# Push
git push --follow-tags

# Create GitHub release
NOTES="$(awk "/^## \[$VERSION\]/,/^## \[/" CHANGELOG.md | grep -v "^## \[" | sed '/^$/d')"
gh release create "$TAG" \
    --repo "$REPO_SLUG" \
    --title "$TAG" \
    --notes "$NOTES"

echo ""
echo "Released $TAG successfully."
