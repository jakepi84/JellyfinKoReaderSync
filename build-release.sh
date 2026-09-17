#!/bin/bash

# Build, validate, package, and publish the Jellyfin KOReader Sync plugin.
#
# ---------------------------------------------------------------------------
# VERSIONING (fixed 2026-09-17)
# ---------------------------------------------------------------------------
# The plugin version has ONE source of truth: the Version element in
# Directory.Build.props. It is never derived from a git tag.
#
# Previously Version fell back to `git describe --tags`, so the maintainer's
# ABI-shaped v12.0.0 tag was fed straight into
#     dotnet build -p:Version=12.0.0.0 -p:AssemblyVersion=12.0.0.0
# Jellyfin reports PluginInfo.Version from the DLL *assembly* version, and the web
# UI fetches the plugin icon from
#     /Plugins/<Id>/<PluginInfo.Version>/Image
# The plugin therefore advertised 12.0.0.0, requested
# /Plugins/<guid>/12.0.0.0/Image, received 404, and rendered a blank tile labelled
# "12.0.0.0" (the installed plugin dir was KOReader Sync_2.0.4.0).
#
# The release tag is now only a GitHub release label. It is derived from the plugin
# version (or passed explicitly) and never influences the built DLL version.
#
# Two guards fail loudly instead of publishing a broken artifact:
#   1. pre-build  - the plugin version must equal the newest version in manifest.json
#                   (add the manifest entry first; Jellyfin reads manifest.json from main)
#   2. post-build - the built DLL's assembly version must equal the plugin version
#
# ---------------------------------------------------------------------------
# USAGE
# ---------------------------------------------------------------------------
#   ./build-release.sh [Version] [ReleaseTag] [PluginName] [RepositorySlug] [AutoTag]
#   ./build-release.sh --Version 2.0.4.1 --AutoTag
#   ./build-release.sh --Version 2.0.4.1 --NoPublish
#
# This host may not have the .NET SDK on PATH. Point DOTNET at a wrapper to build
# in a container instead:
#   DOTNET="docker run --rm -v $PWD:/src -w /src mcr.microsoft.com/dotnet/sdk:9.0 dotnet" \
#       ./build-release.sh --Version 2.0.4.1
#
# Flags: --AutoTag (create + push a missing tag), --NoPublish (build, verify and
# package only; skip the GitHub release and manifest update).

DOTNET=${DOTNET:-dotnet}

# ---------------------------------------------------------------- helpers ----

read_plugin_version() {
    # Single source of truth: the Version element in Directory.Build.props.
    sed -n 's:.*<Version>\([^<]*\)</Version>.*:\1:p' Directory.Build.props 2>/dev/null \
        | head -n 1 | tr -d '[:space:]'
}

normalize_version() {
    # Normalize 3-part input to the 4-part form used by assemblies and manifests.
    local v=$1
    if [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        v="${v}.0"
    fi
    printf '%s' "$v"
}

manifest_version() {
    jq -r '.[0].versions[0].version // empty' manifest.json 2>/dev/null
}

assembly_version_of() {
    # Read the .NET assembly version out of a built DLL via MSBuild's
    # GetAssemblyIdentity task (scripts/verify-assembly-version.proj). DllPath may be
    # relative to the repository root; the project resolves it there.
    $DOTNET msbuild scripts/verify-assembly-version.proj \
        -t:ReportAssemblyVersion -nologo -v:m -p:DllPath="$1" 2>/dev/null \
        | sed -n 's/.*ASSEMBLY_VERSION=//p' | head -n 1 | tr -d '[:space:]'
}

build_release() {
    # Parameters: $1=Version, $2=ReleaseTag, $3=PluginName, $4=RepositorySlug, $5=AutoTag
    local Version=$1
    local ReleaseTag=$2
    local PluginName=$3
    local RepositorySlug=$4
    local AutoTag=$5

    echo "Building Release"
    echo "==================="
    echo ""

    # --- Infer PluginName from current folder if not provided ---
    if [[ -z "$PluginName" ]]; then
        local folders
        folders=$(find . -maxdepth 1 -type d -name "Jellyfin.Plugin.*" | head -n 1)
        if [[ -n "$folders" ]]; then
            PluginName=$(basename "$folders")
        else
            echo "Error: Could not infer PluginName. Please provide -PluginName or ensure a Jellyfin.Plugin.* folder exists." >&2
            return 1
        fi
    fi

    # --- Infer RepositorySlug from git remote if not provided ---
    if [[ -z "$RepositorySlug" ]]; then
        local remote
        remote=$(git config --get remote.origin.url 2>/dev/null)
        # Tolerates SSH host aliases (e.g. git@github-openclaw:owner/repo.git) as well
        # as github.com URLs, and strips any trailing .git.
        if [[ "$remote" =~ [:\/]([^\/:]+\/[^\/]+)$ ]]; then
            RepositorySlug="${BASH_REMATCH[1]%.git}"
        else
            echo "Error: Could not infer RepositorySlug from git remote. Please provide -RepositorySlug." >&2
            return 1
        fi
    fi

    # Convert PluginName (e.g., Jellyfin.Plugin.KoReaderSync) to the artifactName used
    # by manifest.json sourceUrl entries and the maintenance pipeline
    # (jellyfin-koreadersync). The previous pattern left out the "jellyfin-" prefix,
    # producing "koreadersync" and a mismatched download URL.
    local artifactName
    artifactName="jellyfin-$(echo "$PluginName" | sed 's/^Jellyfin\.Plugin\.//' | tr '[:upper:]' '[:lower:]')"
    local targetFramework="net9.0"

    # --- Resolve Version: explicit argument, else Directory.Build.props ------
    # NEVER from a git tag: an ABI-named tag (v12.0.0) previously leaked into the
    # assembly version and broke the plugin icon.
    if [[ -z "$Version" ]]; then
        Version=$(read_plugin_version)
        if [[ -z "$Version" ]]; then
            echo "Error: Could not read the Version element from Directory.Build.props. Pass -Version explicitly." >&2
            return 1
        fi
        echo "Plugin version (Directory.Build.props): $Version"
    fi

    Version=$(normalize_version "$Version")
    if [[ ! "$Version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Version '$Version' is not a 3- or 4-part numeric version." >&2
        return 1
    fi

    # --- Guard 1: the plugin version must match the published manifest -------
    local manifestVer
    manifestVer=$(manifest_version)
    if [[ -z "$manifestVer" ]]; then
        echo "Error: Could not read the newest version from manifest.json." >&2
        return 1
    fi
    if [[ "$manifestVer" != "$Version" ]]; then
        echo "Error: version mismatch - refusing to build a broken artifact." >&2
        echo "  Directory.Build.props / -Version : $Version" >&2
        echo "  manifest.json (newest version)   : $manifestVer" >&2
        echo "" >&2
        echo "Add the $Version entry to manifest.json (with its targetAbi and sourceUrl)" >&2
        echo "before building. Jellyfin reads manifest.json from the main branch, so the" >&2
        echo "manifest must describe the version being released." >&2
        return 1
    fi
    echo "Plugin version matches manifest.json: $manifestVer"

    # --- Determine ReleaseTag (a GitHub release label, not a version source) --
    if [[ -z "$ReleaseTag" ]]; then
        ReleaseTag="v$Version"
    fi

    # --- Setup Artifact Directory ---
    if [ -d "artifacts" ]; then
        rm -rf artifacts
    fi
    mkdir -p "artifacts/$artifactName"

    echo "Plugin: $PluginName"
    echo "Version: $Version"
    echo "Tag: $ReleaseTag"
    echo "Repository: $RepositorySlug"
    echo ""
    echo "Restoring dependencies..."
    $DOTNET restore

    echo "Building project..."
    $DOTNET build --configuration Release --no-restore \
        -p:TreatWarningsAsErrors=false \
        -p:Version="$Version" -p:AssemblyVersion="$Version" -p:FileVersion="$Version"
    if [[ $? -ne 0 ]]; then
        echo "Error: Build failed!" >&2
        return 1
    fi

    echo "Packaging plugin..."
    cp "$PluginName/bin/Release/$targetFramework/$PluginName.dll" "artifacts/$artifactName/"

    # --- Guard 2: the built assembly version must equal the plugin version ---
    # Checked before packaging so a mismatched DLL is never zipped or published.
    local asmVersion
    asmVersion=$(assembly_version_of "artifacts/$artifactName/$PluginName.dll")
    if [[ -z "$asmVersion" ]]; then
        echo "Error: Could not read the assembly version from the built DLL." >&2
        return 1
    fi
    if [[ "$asmVersion" != "$Version" ]]; then
        echo "Error: assembly version mismatch - refusing to publish." >&2
        echo "  built assembly version : $asmVersion" >&2
        echo "  plugin version         : $Version" >&2
        echo "Jellyfin would report PluginInfo.Version=$asmVersion and request" >&2
        echo "/Plugins/<guid>/$asmVersion/Image, which does not exist." >&2
        return 1
    fi
    echo "Assembly version verified: $asmVersion"

    local zipName="${artifactName}_${Version}.zip"
    local zipPath="artifacts/$zipName"

    echo "Creating ZIP: $zipName"
    # A real ZIP archive. This previously used `tar -czf`, which produced a gzip
    # stream with a .zip extension; Jellyfin cannot install that. Fixed timestamps
    # keep the archive checksum reproducible.
    python3 - "$zipPath" "artifacts/$artifactName" <<'PYEOF'
import os, sys, zipfile
zip_path, src_dir = sys.argv[1], sys.argv[2].rstrip("/")
top = os.path.basename(src_dir)
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    for name in sorted(os.listdir(src_dir)):
        full = os.path.join(src_dir, name)
        if not os.path.isfile(full):
            continue
        info = zipfile.ZipInfo(f"{top}/{name}", date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with open(full, "rb") as fh:
            zf.writestr(info, fh.read())
PYEOF
    if [[ ! -f "$zipPath" ]]; then
        echo "Error: Failed to create ZIP file!" >&2
        return 1
    fi

    local size_bytes size_kb
    size_bytes=$(du -b "$zipPath" | awk '{print $1}')
    size_kb=$(awk -v b="$size_bytes" 'BEGIN { printf "%.2f", b / 1024 }')
    echo "ZIP created: $zipName ($size_kb KB)"
    echo ""

    if [[ "$NoPublish" == "true" ]]; then
        echo "--NoPublish set: skipping GitHub release and manifest update."
        echo "Location: $zipPath"
        return 0
    fi

    # --- Validate / create the release tag (publish path only) ---
    # A local build does not need a tag; publishing does, since the release and the
    # manifest sourceUrl both point at it.
    local localTag
    localTag=$(git tag --list "$ReleaseTag" 2>/dev/null)
    if [[ -z "$localTag" ]]; then
        if [[ "$AutoTag" == "true" ]]; then
            echo "Local tag '$ReleaseTag' not found; creating and pushing it."
            git tag "$ReleaseTag"
            if [[ $? -ne 0 ]]; then
                echo "Error: Failed to create local tag '$ReleaseTag'" >&2
                return 1
            fi
            git push origin "$ReleaseTag"
            if [[ $? -ne 0 ]]; then
                echo "Error: Failed to push tag '$ReleaseTag' to origin" >&2
                return 1
            fi
            echo "Tag '$ReleaseTag' created and pushed."
        else
            echo "Error: Local tag '$ReleaseTag' not found. Create it (e.g., 'git tag $ReleaseTag' and 'git push origin $ReleaseTag') or rerun with -AutoTag." >&2
            return 1
        fi
    fi

    # --- GitHub release handling ---
    if ! command -v gh &> /dev/null; then
        echo "Error: GitHub CLI 'gh' not found. Install it from https://cli.github.com/ or run: winget install GitHub.cli" >&2
        return 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' is required to update manifest.json." >&2
        return 1
    fi

    # Ensure remote tag exists
    local remoteTag
    remoteTag=$(git ls-remote --tags origin "$ReleaseTag" 2>/dev/null)
    if [[ -z "$remoteTag" ]]; then
        echo "Remote tag '$ReleaseTag' not found; attempting to push tag to origin."
        git push origin "$ReleaseTag"
        remoteTag=$(git ls-remote --tags origin "$ReleaseTag" 2>/dev/null)
        if [[ -z "$remoteTag" ]]; then
            echo "Error: Remote tag '$ReleaseTag' still not found; cannot create release." >&2
            return 1
        fi
    fi

    # Extract version parts for title/notes
    local verParts=(${Version//./ })
    local shortVer="${verParts[0]}.${verParts[1]}.${verParts[2]}"

    local commitMsg
    commitMsg=$(git log -1 --pretty=%B 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -z "$commitMsg" ]]; then
        commitMsg="Release $ReleaseTag"
    fi

    local title="$PluginName $ReleaseTag"
    local notes="Version $shortVer - $commitMsg"

    if gh release view "$ReleaseTag" --repo "$RepositorySlug" >/dev/null 2>&1; then
        echo "Release '$ReleaseTag' exists; uploading asset with --clobber."
    else
        echo "Creating GitHub release '$ReleaseTag'."
        gh release create "$ReleaseTag" --repo "$RepositorySlug" --title "$title" --notes "$notes"
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to create GitHub release for tag '$ReleaseTag'" >&2
            return 1
        fi
    fi

    gh release upload "$ReleaseTag" "$zipPath" --repo "$RepositorySlug" --clobber
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to upload asset to release '$ReleaseTag'" >&2
        return 1
    fi
    echo "Asset uploaded: $zipName"

    # --- Update manifest.json (its checksum must match the published zip) ---
    echo ""
    echo "Updating manifest.json..."
    if [ -f "update-manifest.sh" ]; then
        ./update-manifest.sh \
            --Version "$Version" \
            --ZipPath "$zipPath" \
            --ReleaseTag "$ReleaseTag" \
            --RepositorySlug "$RepositorySlug"
        if [[ $? -ne 0 ]]; then
            echo "Warning: Manifest update script reported an error." >&2
        else
            echo "Manifest updated."
        fi
    else
        echo "Warning: update-manifest.sh not found; skipping manifest update." >&2
    fi

    echo ""
    echo "Build successful!"
    echo "Location: $zipPath"
    return 0
}

# --- Direct execution -------------------------------------------------------
# Also enables the `./build-release.sh <args...>` call form used by release.sh.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    POS_VERSION=""
    POS_TAG=""
    POS_PLUGIN=""
    POS_SLUG=""
    POS_AUTOTAG=""
    NoPublish=""

    positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --Version|-Version)
                POS_VERSION="$2"; shift 2 ;;
            --ReleaseTag|-ReleaseTag)
                POS_TAG="$2"; shift 2 ;;
            --PluginName|-PluginName)
                POS_PLUGIN="$2"; shift 2 ;;
            --RepositorySlug|-RepositorySlug)
                POS_SLUG="$2"; shift 2 ;;
            --AutoTag|-AutoTag)
                POS_AUTOTAG="true"; shift ;;
            --NoPublish|-NoPublish)
                NoPublish="true"; shift ;;
            *)
                positional+=("$1"); shift ;;
        esac
    done

    if [[ ${#positional[@]} -gt 0 ]]; then
        if [[ -z "$POS_VERSION" ]]; then POS_VERSION="${positional[0]:-}"; fi
        if [[ -z "$POS_TAG" ]]; then POS_TAG="${positional[1]:-}"; fi
        if [[ -z "$POS_PLUGIN" ]]; then POS_PLUGIN="${positional[2]:-}"; fi
        if [[ -z "$POS_SLUG" ]]; then POS_SLUG="${positional[3]:-}"; fi
        if [[ -z "$POS_AUTOTAG" ]]; then POS_AUTOTAG="${positional[4]:-}"; fi
    fi

    build_release "$POS_VERSION" "$POS_TAG" "$POS_PLUGIN" "$POS_SLUG" "$POS_AUTOTAG"
fi
