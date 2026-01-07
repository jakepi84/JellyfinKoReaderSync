param(
    [string]$Version,
    [string]$ReleaseTag,
    [switch]$CreateGitHubRelease,
    [switch]$AutoTag,
    [string]$RepositorySlug = "jakepi84/JellyfinKoReaderSync"
)

Write-Host "Building Release"
Write-Host "================"
Write-Host ""

if ([string]::IsNullOrWhiteSpace($Version)) {
    # Get latest git tag
    $latestTag = git describe --tags --abbrev=0 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($latestTag)) {
        # Convert v1.0.1 to 1.0.1.0
        $tagVersion = $latestTag -replace '^v', ''
        if ($tagVersion -match '^\d+\.\d+\.\d+$') {
            $Version = "$tagVersion.0"
        } else {
            $Version = $tagVersion
        }
        Write-Host "Found latest tag: $latestTag"
    } else {
        Write-Error "Could not get latest git tag. Ensure git is configured and tags exist."
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    # Normalize version to 4-part if user supplied 3-part
    if (-not [string]::IsNullOrWhiteSpace($Version) -and $Version -match '^\d+\.\d+\.\d+$') {
        $Version = "$Version.0"
    }
    $ReleaseTag = "v$($Version.Substring(0, $Version.LastIndexOf('.')))"
}

# Validate local tag exists
$localTag = (git tag --list $ReleaseTag 2>$null)
if ([string]::IsNullOrWhiteSpace($localTag)) {
    if ($AutoTag) {
        Write-Host "Local tag '$ReleaseTag' not found; creating and pushing it."
        git tag $ReleaseTag 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create local tag '$ReleaseTag'"
            exit 1
        }
        git push origin $ReleaseTag 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to push tag '$ReleaseTag' to origin"
            exit 1
        }
        Write-Host "Tag '$ReleaseTag' created and pushed."
    } else {
        Write-Error "Local tag '$ReleaseTag' not found. Create it (e.g., 'git tag $ReleaseTag' and 'git push origin $ReleaseTag') or rerun with -AutoTag."
        exit 1
    }
}

if (Test-Path "artifacts") {
    Remove-Item -Recurse -Force "artifacts"
}
New-Item -ItemType Directory -Path "artifacts/jellyfin-koreader-sync" | Out-Null

Write-Host "Version: $Version"
Write-Host "Tag: $ReleaseTag"
Write-Host ""
Write-Host "Restoring dependencies..."
dotnet restore

Write-Host "Building project..."
dotnet build --configuration Release --no-restore -p:TreatWarningsAsErrors=false -p:Version=$Version -p:AssemblyVersion=$Version -p:FileVersion=$Version
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed!"
    exit 1
}

Write-Host "Packaging plugin..."
Copy-Item "Jellyfin.Plugin.KoReaderSync/bin/Release/net9.0/Jellyfin.Plugin.KoReaderSync.dll" "artifacts/jellyfin-koreader-sync/"

$ZipName = "jellyfin-koreader-sync_$Version.zip"
$ZipPath = Join-Path -Path "artifacts" -ChildPath $ZipName

Write-Host "Creating ZIP: $ZipName"
Compress-Archive -Path "artifacts/jellyfin-koreader-sync" -DestinationPath $ZipPath -Force

if (Test-Path $ZipPath) {
    $size = (Get-Item $ZipPath).Length / 1KB
    Write-Host "ZIP created: $ZipName ($([Math]::Round($size, 2)) KB)"
    Write-Host ""
    Write-Host "Updating manifest.json..."
    if (Test-Path "update-manifest.ps1") {
        & ./update-manifest.ps1 -Version $Version -ZipPath $ZipPath -ReleaseTag $ReleaseTag
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Manifest update script reported an error."
        } else {
            Write-Host "Manifest updated."
        }
    } else {
        Write-Warning "update-manifest.ps1 not found; skipping manifest update."
    }

    # GitHub release handling
    $remoteTag = (git ls-remote --tags origin $ReleaseTag 2>$null)
    if ($CreateGitHubRelease) {
        $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
        if (-not $ghCmd) {
            Write-Error "GitHub CLI 'gh' not found. Install it from https://cli.github.com/ or run: winget install GitHub.cli"
            exit 1
        }

        # Ensure remote tag exists if AutoTag pushed or manual push done
        if ([string]::IsNullOrWhiteSpace($remoteTag)) {
            Write-Host "Remote tag '$ReleaseTag' not found; attempting to push tag to origin."
            git push origin $ReleaseTag 2>&1 | Write-Host
            $remoteTag = (git ls-remote --tags origin $ReleaseTag 2>$null)
            if ([string]::IsNullOrWhiteSpace($remoteTag)) {
                Write-Error "Remote tag '$ReleaseTag' still not found; cannot create release."
                exit 1
            }
        }

        # Determine if release exists
        gh release view $ReleaseTag --repo $RepositorySlug 2>$null
        $releaseExists = ($LASTEXITCODE -eq 0)

        $verParts = $Version.Split('.')
        $shortVer = if ($verParts.Length -ge 3) { "$($verParts[0]).$($verParts[1]).$($verParts[2])" } else { $Version }
        $commitMsg = try { (git log -1 --pretty=%B 2>$null).Trim() } catch { "Release $ReleaseTag" }
        $title = "KOReader Sync $ReleaseTag"
        $notes = "Version $shortVer - $commitMsg"

        if (-not $releaseExists) {
            Write-Host "Creating GitHub release '$ReleaseTag' and uploading asset."
            gh release create $ReleaseTag $ZipPath --repo $RepositorySlug --title $title --notes $notes 2>&1 | Write-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create GitHub release for tag '$ReleaseTag'"
                exit 1
            }
            Write-Host "GitHub release created and asset uploaded."
        } else {
            Write-Host "Release '$ReleaseTag' already exists; ensuring asset is uploaded."
            $zipName = Split-Path $ZipPath -Leaf
            $assetNames = gh release view $ReleaseTag --repo $RepositorySlug --json assets --jq ".assets[].name" 2>$null
            if ($assetNames -notcontains $zipName) {
                gh release upload $ReleaseTag $ZipPath --repo $RepositorySlug 2>&1 | Write-Host
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to upload asset to existing release '$ReleaseTag'"
                    exit 1
                }
                Write-Host "Asset '$zipName' uploaded to release."
            } else {
                Write-Host "Asset '$zipName' already present; skipping upload."
            }
        }
    } else {
        if ([string]::IsNullOrWhiteSpace($remoteTag)) {
            Write-Error "Remote tag '$ReleaseTag' not found on origin. Push the tag or rerun with -CreateGitHubRelease to create the release automatically."
            exit 1
        }
        Write-Host "Remote tag found; skipping release creation."
    }
    Write-Host ""
    Write-Host "Build successful!"
    Write-Host "Location: $ZipPath"
} else {
    Write-Error "Failed to create ZIP file!"
    exit 1
}
