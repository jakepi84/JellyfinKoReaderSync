#!/bin/bash

# Function to update manifest.json
update_manifest() {
    # Parameters: --Version, --ZipPath, --ReleaseTag, --RepositorySlug
    local Version=""
    local ZipPath=""
    local ReleaseTag=""
    local RepositorySlug=""

    # Simple argument parsing for demonstration (assuming positional or named arguments)
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --Version) Version="$2"; shift ;;
            --ZipPath) ZipPath="$2"; shift ;;
            --ReleaseTag) ReleaseTag="$2"; shift ;;
            --RepositorySlug) RepositorySlug="$2"; shift ;;
            *) ;;
        esac
        shift
    done

    echo "Updating manifest.json"
    echo "====================="
    echo ""
    echo "Version: $Version"
    echo "Tag: $ReleaseTag"
    echo "ZIP: $ZipPath"
    echo ""

    if [ ! -f "manifest.json" ]; then
        echo "Error: manifest.json not found!" >&2
        return 1
    fi

    # Calculate MD5 checksum
    if [ -f "$ZipPath" ]; then
        local checksum
        checksum=$(md5sum "$ZipPath" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
        echo "Checksum: $checksum"
    else
        echo "Error: ZIP file not found for checksum calculation: $ZipPath" >&2
        return 1
    fi

    # Get targetAbi from build.yaml
    local buildYaml
    buildYaml=$(cat build.yaml 2>/dev/null)
    local targetAbi="10.11.0.0"
    if [[ -n "$buildYaml" ]]; then
        targetAbi=$(echo "$buildYaml" | grep -oP 'targetAbi:\s*"?([^"\n]+)"?' | head -n 1 | awk '{print $2}')
    fi

    # Build changelog
    local changelog
    local commitMessage
    commitMessage=$(git log -1 --pretty=%B 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [[ -n "$commitMessage" ]]; then
        local verParts=(${Version//./ })
        local shortVer=${verParts[0]}.${verParts[1]}.${verParts[2]:-$(echo "$Version" | cut -d. -f3)}
        changelog="Version $shortVer - $commitMessage"
    elif [[ -n "$buildYaml" ]]; then
        changelog=$(echo "$buildYaml" | grep -oP 'changelog:\s*>?\s*(.+?)(?=^[a-z]|$)')
        changelog=$(echo "$changelog" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
        changelog="Release version $Version"
    fi

    echo "TargetAbi: $targetAbi"
    echo "Changelog: $changelog"

    local repositoryUrl="https://github.com/$RepositorySlug"
    local sourceUrl="$repositoryUrl/releases/download/$ReleaseTag/$(basename "$ZipPath")"
    echo "SourceUrl: $sourceUrl"
    echo ""

    # Get timestamp in ISO 8601 format
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Construct the new version object as a JSON fragment
    local newVersionJson
    newVersionJson=$(jq -n \
        --arg version "$Version" \
        --arg changelog "$changelog" \
        --arg targetAbi "$targetAbi" \
        --arg sourceUrl "$sourceUrl" \
        --arg checksum "$checksum" \
        --arg timestamp "$timestamp" \
        '{version: $version, changelog: $changelog, targetAbi: $targetAbi, sourceUrl: $sourceUrl, checksum: $checksum, timestamp: $timestamp}')

    # Read existing manifest and update
    local manifestJson
    manifestJson=$(cat manifest.json)

    # Use jq to update the JSON structure
    # This assumes the manifest structure is an object containing an array named 'packages'
    # and that the first element of that array has a 'versions' array.
    
    # Check if the version already exists to prevent unnecessary updates
    local existingEntryCheck
    existingEntryCheck=$(echo "$manifestJson" | jq -r --arg v "$Version" --arg c "$checksum" --arg su "$sourceUrl" --arg ta "$targetAbi" --arg cl "$changelog" '.packages[0].versions[] | select(.version == $v and .checksum == $c and .sourceUrl == $su and .targetAbi == $ta and .changelog == $cl)' 2>/dev/null)

    if [[ -n "$existingEntryCheck" ]]; then
        echo "Manifest already up to date; no changes made."
        return 0
    fi

    # Construct the final JSON using jq to replace/prepend the version
    local updatedJson
    updatedJson=$(echo "$manifestJson" | jq --argjson newVersion "$newVersionJson" '.packages[0].versions += [$newVersion]' 2>/dev/null)

    if [[ $? -ne 0 || -z "$updatedJson" ]]; then
        echo "Error processing JSON structure. Check manifest.json format." >&2
        return 1
    fi

    echo "$updatedJson" > manifest.json

    echo "Updated manifest.json"
    echo ""
    echo "New entry added:"
    echo "  Version: $Version"
    echo "  TargetAbi: $targetAbi"
    echo "  Checksum: $checksum"
}

# Example usage: update_manifest --Version "1.2.3" --ZipPath "artifacts/jellyfin-1.2.3.zip" --ReleaseTag "v1.2" --RepositorySlug "user/repo"