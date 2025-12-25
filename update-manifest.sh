#!/bin/bash
# Update manifest.json with new plugin version
# This script should be run after building the plugin

set -e

VERSION="$1"
ZIP_FILE="$2"

if [ -z "$VERSION" ] || [ -z "$ZIP_FILE" ]; then
    echo "Usage: $0 <version> <zip_file>"
    exit 1
fi

if [ ! -f "$ZIP_FILE" ]; then
    echo "Error: ZIP file not found: $ZIP_FILE"
    exit 1
fi

echo "Updating manifest.json for version $VERSION..."

# Calculate checksum (Jellyfin uses MD5 for plugin checksums)
CHECKSUM=$(md5sum "$ZIP_FILE" | awk '{print toupper($1)}')
echo "Checksum (MD5): $CHECKSUM"

# Get current timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "Timestamp: $TIMESTAMP"

# Extract changelog from build.yaml
CHANGELOG=$(grep -A 100 "^changelog:" build.yaml | tail -n +2 | sed '/^[a-zA-Z]/,$d' | sed 's/^  - /- /g' | sed 's/^  //g')

# Extract targetAbi from build.yaml (handles both quoted and unquoted values)
TARGET_ABI=$(grep "^targetAbi:" build.yaml | sed 's/^targetAbi:[[:space:]]*"\?\([^"]*\)"\?/\1/')

# Get repository URL from git remote
REPO_URL=$(git config --get remote.origin.url | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')

# Extract tag version (X.Y.Z format)
TAG="v$(echo $VERSION | cut -d. -f1-3)"

# Construct sourceUrl
SOURCE_URL="${REPO_URL}/releases/download/${TAG}/jellyfin-koreader-sync_${VERSION}.zip"

# Create new version entry
NEW_VERSION=$(jq -n \
  --arg version "$VERSION" \
  --arg changelog "$CHANGELOG" \
  --arg targetAbi "$TARGET_ABI" \
  --arg sourceUrl "$SOURCE_URL" \
  --arg checksum "$CHECKSUM" \
  --arg timestamp "$TIMESTAMP" \
  '{
    version: $version,
    changelog: $changelog,
    targetAbi: $targetAbi,
    sourceUrl: $sourceUrl,
    checksum: $checksum,
    timestamp: $timestamp
  }')

# Update manifest.json
# First, remove any existing entry with the same version from the first package
jq --arg version "$VERSION" \
  '.[0].versions = [.[0].versions[] | select(.version != $version)]' \
  manifest.json > manifest.tmp.json

# Then add the new version at the beginning of the first package
jq --argjson newVersion "$NEW_VERSION" \
  '.[0].versions = [$newVersion] + .[0].versions' \
  manifest.tmp.json > manifest.json

rm manifest.tmp.json

echo "✓ manifest.json updated successfully!"
echo "Version $VERSION added with:"
echo "  - TargetAbi: $TARGET_ABI"
echo "  - SourceUrl: $SOURCE_URL"
echo "  - Checksum: $CHECKSUM"
echo "  - Timestamp: $TIMESTAMP"
