#!/bin/bash
# scripts/changelog.sh
# Auto-generate CHANGELOG.md dari git commits
# Maintainer: irfanFRizki

VERSION="${1:-1.0.0}"
DATE=$(date +"%Y-%m-%d")
CHANGELOG_FILE="CHANGELOG.md"
TMP_FILE="/tmp/changelog_new.md"

echo "## v${VERSION} - ${DATE}" > "$TMP_FILE"
echo "" >> "$TMP_FILE"

# Ambil commits sejak tag terakhir
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -n "$LAST_TAG" ]; then
    git log "${LAST_TAG}..HEAD" --pretty=format:"* %s (%an)" --no-merges 2>/dev/null >> "$TMP_FILE"
else
    git log --pretty=format:"* %s (%an)" --no-merges -20 2>/dev/null >> "$TMP_FILE"
fi

echo "" >> "$TMP_FILE"
echo "" >> "$TMP_FILE"

# Gabung dengan changelog lama
if [ -f "$CHANGELOG_FILE" ]; then
    cat "$CHANGELOG_FILE" >> "$TMP_FILE"
fi

mv "$TMP_FILE" "$CHANGELOG_FILE"

echo "[INFO] CHANGELOG.md diperbarui untuk v${VERSION}"
