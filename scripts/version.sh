#!/bin/bash

VERSION=$(cat VERSION)

MAJOR=$(echo $VERSION | cut -d. -f1)
MINOR=$(echo $VERSION | cut -d. -f2)
PATCH=$(echo $VERSION | cut -d. -f3)

LAST_MSG=$(git log -1 --pretty=%B)

if [[ $LAST_MSG == *"BREAKING"* ]]; then
    MAJOR=$((MAJOR+1))
    MINOR=0
    PATCH=0

elif [[ $LAST_MSG == *"feat"* ]]; then
    MINOR=$((MINOR+1))
    PATCH=0

else
    PATCH=$((PATCH+1))
fi

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

echo $NEW_VERSION > VERSION

echo $NEW_VERSION
