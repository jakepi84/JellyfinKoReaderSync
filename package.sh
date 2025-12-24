#!/bin/bash
# Package script for Jellyfin KOReader Sync Plugin

set -e

# Extract version from Directory.Build.props if not provided
if [ -z "$1" ]; then
    VERSION=$(xmlstarlet sel -t -v "//Version" Directory.Build.props 2>/dev/null || echo "1.0.0.0")
else
    VERSION="$1"
fi

OUTPUT_DIR="./release"

echo "Building Jellyfin KOReader Sync Plugin version $VERSION..."

# Clean previous builds
echo "Cleaning previous builds..."
dotnet clean --configuration Release

# Restore dependencies
echo "Restoring dependencies..."
dotnet restore

# Build the plugin
echo "Building plugin..."
dotnet build --configuration Release --no-restore -p:TreatWarningsAsErrors=false

# Create output directory
echo "Creating release package..."
mkdir -p "$OUTPUT_DIR"

# Copy the DLL to output
cp Jellyfin.Plugin.KoReaderSync/bin/Release/net9.0/Jellyfin.Plugin.KoReaderSync.dll "$OUTPUT_DIR/"

# Set deterministic timestamps for reproducible builds (Unix epoch)
find "$OUTPUT_DIR" -exec touch -d '1970-01-01 00:00:00 UTC' {} +

# Create a zip file
cd "$OUTPUT_DIR"
ZIP_NAME="jellyfin-koreader-sync_${VERSION}.zip"
zip -r -X "$ZIP_NAME" Jellyfin.Plugin.KoReaderSync.dll

echo ""
echo "✓ Plugin built successfully!"
echo "✓ Package created: $OUTPUT_DIR/$ZIP_NAME"
echo ""
echo "To install:"
echo "1. Extract the DLL from the zip file"
echo "2. Copy it to your Jellyfin plugins folder:"
echo "   - Linux: /var/lib/jellyfin/plugins/KOReader Sync/"
echo "   - Windows: %ProgramData%\\Jellyfin\\Server\\plugins\\KOReader Sync\\"
echo "3. Restart Jellyfin"
echo ""
