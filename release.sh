#!/bin/bash

# Function to orchestrate the release process
release_builder() {
    # Parameters: $1=Version, $2=ReleaseTag, $3=PluginName, $4=RepositorySlug, $5=AutoTag
    local Version=$1
    local ReleaseTag=$2
    local PluginName=$3
    local RepositorySlug=$4
    local AutoTag=$5

    echo ""
    echo "$PluginName Release Builder"
    echo "======================================="
    echo ""

    # Call the build script
    ./build-release.sh \
        "$Version" \
        "$ReleaseTag" \
        "$PluginName" \
        "$RepositorySlug" \
        "$AutoTag"

    if [[ $? -ne 0 ]]; then
        echo ""
        echo "FAILURE!"
        echo "==================="
        echo ""
        return 1
    fi

    echo ""
    echo "SUCCESS!"
    echo "========"
    echo ""
    echo "Release complete for $PluginName v$Version"
    echo "ZIP location: artifacts/$artifactName_${Version}.zip"
    echo ""
    echo "Next steps:"
    echo "1. Review manifest.json changes"
    echo "2. Commit and push:"
    echo "   git add manifest.json"
    echo "   git commit -m 'Update manifest for version $Version'"
    echo "   git push origin main"
}

# Example usage: release_builder "$1" "$2" "$3" "$4" "$5"