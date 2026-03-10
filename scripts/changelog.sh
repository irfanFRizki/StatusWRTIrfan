#!/bin/bash

VERSION=$1

echo "## v$VERSION - $(date +%Y-%m-%d)" >> CHANGELOG.md
git log -5 --pretty=format:"- %s" >> CHANGELOG.md
echo "" >> CHANGELOG.md
echo "" >> CHANGELOG.md
