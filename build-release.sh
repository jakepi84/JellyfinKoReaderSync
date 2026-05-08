#!/bin/bash

# Function to handle build and release process
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
        # Find the first directory matching the pattern
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
        if [[ "$remote" =~ github.com[:/](.+/.+)$ ]]; then
            RepositorySlug="${BASH_REMATCH[1]}"
        else
            echo "Error: Could not infer RepositorySlug from git remote. Please provide -RepositorySlug." >&2
            return 1
        fi
    fi

    # Convert PluginName (e.g., Jellyfin.Plugin.KoReaderSync) to artifactName (jellyfin-koreadersync)
    local artifactName=$(echo "$PluginName" | sed 's/Jellyfin\.Plugin\.//g' | tr '[:upper:]' '[:lower:]')
    local targetFramework="net9.0"

    # --- Determine Version ---
    if [[ -z "$Version" ]]; then
        # Get latest git tag
        local latestTag
        latestTag=$(git describe --tags --abbrev=0 2>/dev/null)
        if [[ $? -eq 0 && -n "$latestTag" ]]; then
            # Convert v1.0.1 to 1.0.1.0
            local tagVersion="${latestTag#v}"
            if [[ "$tagVersion" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                Version="${tagVersion}.0"
            else
                Version="$tagVersion"
            fi
            echo "Found latest tag: $latestTag"
        else
            echo "Error: Could not get latest git tag. Ensure git is configured and tags exist." >&2
            return 1
        fi
    fi

    # --- Determine ReleaseTag ---
    if [[ -z "$ReleaseTag" ]]; then
        # Normalize version to 4-part if user supplied 3-part
        if [[ -n "$Version" && "$Version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            Version="${Version}.0"
        fi
        # Extract major.minor.patch for the tag prefix
        ReleaseTag="v${Version%%.*}"
    fi

    # --- Validate local tag exists ---
    local localTag
    localTag=$(git tag --list "$ReleaseTag" 2>/dev/null)
    if [[ -z "$localTag" ]]; then
        if [[ "$AutoTag" == "true" ]]; then
            echo "Local tag '$ReleaseTag' not found; creating and pushing it."
            git tag "$ReleaseTag" 2>&1 | tee /dev/stderr
            if [[ $? -ne 0 ]]; then
                echo "Error: Failed to create local tag '$ReleaseTag'" >&2
                return 1
            fi
            git push origin "$ReleaseTag" 2>&1 | tee /dev/stderr
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
    dotnet restore

    echo "Building project..."
    dotnet build --configuration Release --no-restore -p:TreatWarningsAsErrors=false -p:Version="$Version" -p:AssemblyVersion="$Version" -p:FileVersion="$Version"
    if [[ $? -ne 0 ]]; then
        echo "Error: Build failed!" >&2
        return 1
    fi

    echo "Packaging plugin..."
    cp "$PluginName/bin/Release/$targetFramework/$PluginName.dll" "artifacts/$artifactName/"

    local zipName="${artifactName}_${Version}.zip"
    local zipPath="artifacts/$zipName"

    echo "Creating ZIP: $zipName"
    # Using tar to create a zip archive from the directory contents
    tar -czf "$zipPath" -C "artifacts" "$artifactName"

    if [ -f "$zipPath" ]; then
        # Calculate size in KB
        local size_bytes=$(du -b "$zipPath" | awk '{print $1}')
        local size_kb=$(echo "scale=2; $size_bytes / 1024" | bc)
        echo "ZIP created: $zipName ($size_kb KB)"
        echo ""

        # GitHub release handling
        local remoteTag
        remoteTag=$(git ls-remote --tags origin "$ReleaseTag" 2>/dev/null)
        
        # Check for 'gh' CLI
        if ! command -v gh &> /dev/null; then
            echo "Error: GitHub CLI 'gh' not found. Install it from https://cli.github.com/ or run: winget install GitHub.cli" >&2
            return 1
        fi

        # Ensure remote tag exists
        if [[ -z "$remoteTag" ]]; then
            echo "Remote tag '$ReleaseTag' not found; attempting to push tag to origin."
            git push origin "$ReleaseTag" 2>&1 | tee /dev/stderr
            remoteTag=$(git ls-remote --tags origin "$ReleaseTag" 2>/dev/null)
            if [[ -z "$remoteTag" ]]; then
                echo "Error: Remote tag '$ReleaseTag' still not found; cannot create release." >&2
                return 1
            fi
        fi

        # Determine if release exists
        gh release view "$ReleaseTag" --repo "$RepositorySlug" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            releaseExists=true
        else
            releaseExists=false
        fi

        # Extract version parts for title/notes
        local verParts=(${Version//./ })
        local shortVer=${verParts[0]}.${verParts[1]}.${verParts[2]:-$(echo "$Version" | cut -d. -f3)}
        
        # Get commit message
        local commitMsg
        commitMsg=$(git log -1 --pretty=%B 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$commitMsg" ]]; then
            commitMsg="Release $ReleaseTag"
        fi
        
        local title="$PluginName $ReleaseTag"
        local notes="Version $shortVer - $commitMsg"

        local assetUploadNeeded=true
        
        if [[ "$releaseExists" == true ]]; then
            echo "Release '$ReleaseTag' already exists; checking if asset upload is needed."
            local zipName_leaf=$(basename "$zipPath")
            # Get existing asset names using jq
            local assetNames
            assetNames=$(gh release view "$ReleaseTag" --repo "$RepositorySlug" --json assets --jq ".assets[].name" 2>/dev/null)
            
            if [[ ! "$assetNames" =~ "$zipName_leaf" ]]; then
                echo "Asset '$zipName_leaf' not present; uploading."
                gh release upload "$ReleaseTag" "$zipPath" --repo "$RepositorySlug" 2>&1 | tee /dev/stderr
                if [[ $? -ne 0 ]]; then
                    echo "Error: Failed to upload asset to existing release '$ReleaseTag'" >&2
                    return 1
                fi
                echo "Asset '$zipName_leaf' uploaded to release."
                assetUploadNeeded=false
            else
                echo "Asset '$zipName_leaf' already present; skipping upload."
                echo "WARNING: Skipping manifest update since asset is already on GitHub release."
                echo "To update the manifest with a new version, create a new version tag and re-run the build."
                assetUploadNeeded=true
            fi
        else
            echo "Creating GitHub release '$ReleaseTag' and uploading asset."
            gh release create "$ReleaseTag" "$zipPath" --repo "$RepositorySlug" --title "$title" --notes "$notes" 2>&1 | tee /dev/stderr
            if [[ $? -ne 0 ]]; then
                echo "Error: Failed to create GitHub release for tag '$ReleaseTag'" >&2
                return 1
            fi
            echo "GitHub release created and asset uploaded."
            assetUploadNeeded=false
        fi

        # Only update manifest if we uploaded a new asset or created a new release
        if [[ "$assetUploadNeeded" == false ]]; then
            echo ""
            echo "Updating manifest.json..."
            if [ -f "update-manifest.sh" ]; then
                ./update-manifest.sh \
                    --Version "$Version" \
                    --ZipPath "$zipPath" \
                    --ReleaseTag "$ReleaseTag" \
                    --RepositorySlug "$RepositorySlug"
                if [[ $? -ne 0 ]]; then
                    echo "Warning: Manifest update script reported an error."
                else
                    echo "Manifest updated."
                fi
            else
                echo "Warning: update-manifest.sh not found; skipping manifest update."
            fi
        fi
        
        echo ""
        echo "Build successful!"
        echo "Location: $zipPath"
    else
        echo "Error: Failed to create ZIP file!" >&2
        return 1
    fi
}

# Example usage (assuming parameters are passed when running the script)
# build_release "$1" "$2" "$3" "$4" "$5"