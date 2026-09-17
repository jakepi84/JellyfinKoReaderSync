#!/bin/bash

# Update manifest.json for a Jellyfin plugin release.
#
# manifest.json is a TOP-LEVEL ARRAY of package objects, not {"packages": [...]}.
# The previous implementation indexed '.packages[0].versions', so jq errored on
# every run ("Cannot index array with string") and the manifest silently never
# updated (fixed 2026-09-17). It also could not be executed directly - the
# function was never invoked - while build-release.sh calls it as
# `./update-manifest.sh`.
#
# Usage:
#   ./update-manifest.sh --Version 2.0.4.1 \
#       --ZipPath artifacts/jellyfin-koreadersync_2.0.4.1.zip \
#       --ReleaseTag v2.0.4.1 \
#       --RepositorySlug jakepi84/JellyfinKoReaderSync \
#       [--TargetAbi 12.0.0.0] [--Changelog "Version 2.0.4.1 - ..."]

update_manifest() {
    local Version=""
    local ZipPath=""
    local ReleaseTag=""
    local RepositorySlug=""
    local TargetAbi=""
    local ChangelogOverride=""

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --Version) Version="$2"; shift 2 ;;
            --ZipPath) ZipPath="$2"; shift 2 ;;
            --ReleaseTag) ReleaseTag="$2"; shift 2 ;;
            --RepositorySlug) RepositorySlug="$2"; shift 2 ;;
            --TargetAbi) TargetAbi="$2"; shift 2 ;;
            --Changelog) ChangelogOverride="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    echo "Updating manifest.json"
    echo "====================="
    echo ""

    if [[ -z "$Version" ]]; then
        echo "Error: --Version is required." >&2
        return 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' is required to update manifest.json." >&2
        return 1
    fi
    if [ ! -f "manifest.json" ]; then
        echo "Error: manifest.json not found!" >&2
        return 1
    fi
    if [[ -z "$ZipPath" || ! -f "$ZipPath" ]]; then
        echo "Error: ZIP file not found for checksum calculation: $ZipPath" >&2
        return 1
    fi
    if [[ -z "$RepositorySlug" ]]; then
        echo "Error: --RepositorySlug is required." >&2
        return 1
    fi

    echo "Version: $Version"
    echo "Tag: $ReleaseTag"
    echo "ZIP: $ZipPath"
    echo ""

    # Calculate MD5 checksum of the published artifact
    local checksum
    checksum=$(md5sum "$ZipPath" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    echo "Checksum: $checksum"

    # targetAbi: explicit argument, else carry over the current newest entry.
    # (There is no build.yaml in this repo; the previous default of 10.11.0.0
    # would have silently downgraded a 12.x plugin.)
    if [[ -z "$TargetAbi" ]]; then
        TargetAbi=$(jq -r '.[0].versions[0].targetAbi // empty' manifest.json 2>/dev/null)
    fi
    if [[ -z "$TargetAbi" ]]; then
        echo "Error: Could not determine targetAbi; pass --TargetAbi." >&2
        return 1
    fi

    # Build changelog from the latest commit message (or an explicit override)
    local commitMessage
    commitMessage=$(git log -1 --pretty=%B 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    local changelog
    if [[ -n "$ChangelogOverride" ]]; then
        changelog="$ChangelogOverride"
    elif [[ -n "$commitMessage" ]]; then
        local verParts=(${Version//./ })
        local shortVer="${verParts[0]}.${verParts[1]}.${verParts[2]}"
        changelog="Version $shortVer - $commitMessage"
    else
        changelog="Release version $Version"
    fi

    if [[ -z "$ReleaseTag" ]]; then
        ReleaseTag="v$Version"
    fi

    local repositoryUrl="https://github.com/$RepositorySlug"
    local sourceUrl="$repositoryUrl/releases/download/$ReleaseTag/$(basename "$ZipPath")"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "TargetAbi: $TargetAbi"
    echo "Changelog: $changelog"
    echo "SourceUrl: $sourceUrl"
    echo ""

    local newVersionJson
    newVersionJson=$(jq -n \
        --arg version "$Version" \
        --arg changelog "$changelog" \
        --arg targetAbi "$TargetAbi" \
        --arg sourceUrl "$sourceUrl" \
        --arg checksum "$checksum" \
        --arg timestamp "$timestamp" \
        '{version: $version, changelog: $changelog, targetAbi: $targetAbi, sourceUrl: $sourceUrl, checksum: $checksum, timestamp: $timestamp}')

    # Replace the entry for this version if present, otherwise prepend it so the
    # newest version stays first (Jellyfin picks the newest compatible entry).
    local tmp
    tmp=$(mktemp)
    jq --argjson nv "$newVersionJson" --arg v "$Version" '
        if ([.[0].versions[]?.version] | index($v)) != null then
            .[0].versions = [.[0].versions[] | if .version == $v then $nv else . end]
        else
            .[0].versions = [$nv] + .[0].versions
        end
    ' manifest.json > "$tmp"

    if [[ $? -ne 0 || ! -s "$tmp" ]]; then
        echo "Error processing JSON structure. Check manifest.json format." >&2
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" manifest.json

    echo "Updated manifest.json"
    echo ""
    echo "Entry written:"
    echo "  Version: $Version"
    echo "  TargetAbi: $TargetAbi"
    echo "  Checksum: $checksum"
    return 0
}

# --- Direct execution -------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    update_manifest "$@"
fi
