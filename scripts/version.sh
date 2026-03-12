#!/bin/bash
# scripts/version.sh
# Auto-generate versi berdasarkan tag git terakhir
# Format: MAJOR.MINOR.PATCH
# Maintainer: irfanFRizki

VERSION_FILE="VERSION"

# Cek apakah ada file VERSION
if [ -f "$VERSION_FILE" ]; then
    CURRENT=$(cat "$VERSION_FILE" | tr -d '[:space:]')
else
    CURRENT="1.0.0"
fi

# Parse versi
MAJOR=$(echo "$CURRENT" | cut -d. -f1)
MINOR=$(echo "$CURRENT" | cut -d. -f2)
PATCH=$(echo "$CURRENT" | cut -d. -f3)

# Auto-increment patch
PATCH=$((PATCH + 1))

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# Simpan versi baru
echo "$NEW_VERSION" > "$VERSION_FILE"

# Output versi (digunakan oleh workflow)
echo "$NEW_VERSION"
