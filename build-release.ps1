<#
  .SYNOPSIS
  Builds the Jellyfin KOReader Sync plugin, packages it, and optionally creates a GitHub release.

  .DESCRIPTION
  This script handles the full release workflow:
    1. Infers plugin name and repo slug from the local directory and git remote
    2. Resolves the version from -Version, or falls back to Directory.Build.props
       (never from a git tag: an ABI-shaped tag once leaked into the assembly version)
    3. Builds the plugin DLL via dotnet (net9.0)
    4. Packages the DLL into a zip artifact
    5. Creates (or updates) a GitHub release with the zip attached
    6. Updates manifest.json with checksum and source URL via update-manifest.ps1

  .PARAMETER Version
  Four-part version string (e.g. "2.0.4.1"). If omitted, read from Directory.Build.props.

  .PARAMETER ReleaseTag
  Git tag for the release (e.g. "v2.0.3"). If omitted, derived from Version.

  .PARAMETER PluginName
  Project folder name (e.g. "Jellyfin.Plugin.KoReaderSync"). If omitted, auto-detected.

  .PARAMETER RepositorySlug
  GitHub repo slug (e.g. "jakepi84/JellyfinKoReaderSync"). If omitted, inferred from git remote.

  .PARAMETER CreateGitHubRelease
  Whether to create a GitHub release. Defaults to $true.

  .PARAMETER AutoTag
  If the local tag doesn't exist, create and push it automatically instead of erroring.

  .EXAMPLE
  ./build-release.ps1 -Version 2.0.4.1 -AutoTag
  # Builds plugin version 2.0.4.1, creates tag v2.0.4.1, and publishes a GitHub release.
#>
param(
    [string]$Version,
    [string]$ReleaseTag,
    [string]$PluginName,
    [string]$RepositorySlug,
    [switch]$CreateGitHubRelease = $true,
    [switch]$AutoTag
)

# ── Phase 1: Resolve parameters ─────────────────────────────────────────────
# Auto-detect plugin name and repo slug from the local environment so the script
# can be run without arguments in most cases.

Write-Host "Building Release"
Write-Host "================"
Write-Host ""

# Infer PluginName from current folder if not provided
if ([string]::IsNullOrWhiteSpace($PluginName)) {
    $folders = Get-ChildItem -Directory -Filter "Jellyfin.Plugin.*" | Select-Object -First 1
    if ($folders) {
        $PluginName = $folders.Name
    } else {
        Write-Error "Could not infer PluginName. Please provide -PluginName or ensure a Jellyfin.Plugin.* folder exists."
        exit 1
    }
}

# Infer RepositorySlug from git remote if not provided
if ([string]::IsNullOrWhiteSpace($RepositorySlug)) {
    $remote = (git config --get remote.origin.url 2>$null) -replace '\.git$', ''
    if ($remote -match 'github.com[:/](.+/.+)$') {
        $RepositorySlug = $matches[1]
    } else {
        Write-Error "Could not infer RepositorySlug from git remote. Please provide -RepositorySlug."
        exit 1
    }
}

# Normalize the artifact name (e.g. Jellyfin.Plugin.KoReaderSync → jellyfin-koreadersync)
$artifactName = $PluginName -replace 'Jellyfin\.Plugin\.', 'jellyfin-' | ForEach-Object { $_.ToLower() }
$targetFramework = "net9.0"

# ── Phase 2: Resolve version and tag ─────────────────────────────────────────
# The plugin version comes from Directory.Build.props (single source of truth).
# It is deliberately NOT derived from a git tag: the ABI-shaped v12.0.0 tag was
# once fed into -p:AssemblyVersion, which made Jellyfin advertise 12.0.0.0 and
# request /Plugins/<Id>/12.0.0.0/Image (404 -> blank icon tile).

if ([string]::IsNullOrWhiteSpace($Version)) {
    $propsPath = "Directory.Build.props"
    if (Test-Path $propsPath) {
        $propsXml = [xml](Get-Content $propsPath -Raw)
        $Version = $propsXml.Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
    }
    if ([string]::IsNullOrWhiteSpace($Version)) {
        Write-Error "Could not read the Version element from Directory.Build.props. Pass -Version explicitly."
        exit 1
    }
    Write-Host "Plugin version (Directory.Build.props): $Version"
}

# Normalize 3-part input to the 4-part form used by assemblies and manifests
if ($Version -match '^\d+\.\d+\.\d+$') {
    $Version = "$Version.0"
}
if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    Write-Error "Version '$Version' is not a 3- or 4-part numeric version."
    exit 1
}

# Guard 1: the plugin version must match the newest entry in manifest.json.
$manifestJson = Get-Content "manifest.json" -Raw | ConvertFrom-Json
if ($manifestJson -isnot [Array]) { $manifestJson = @($manifestJson) }
$manifestVer = $manifestJson[0].versions[0].version
if ($manifestVer -ne $Version) {
    Write-Error "Version mismatch - refusing to build a broken artifact.`n  Version: $Version`n  manifest.json: $manifestVer`nAdd the $Version entry to manifest.json before building."
    exit 1
}
Write-Host "Plugin version matches manifest.json: $manifestVer"

if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    # A GitHub release label derived from the plugin version. It never influences
    # the built DLL version. Note the existing v2.0.4 tag, so a 2.0.4.1 release
    # must use the distinct v2.0.4.1 tag.
    $ReleaseTag = "v$Version"
}

# ── Phase 3: Validate / create git tag ───────────────────────────────────────
# The release needs a tag. If it doesn't exist locally, either create it
# (with -AutoTag) or error out.

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

# ── Phase 4: Build and package ────────────────────────────────────────────────
# Clean artifacts dir, restore deps, build, and zip the DLL.

if (Test-Path "artifacts") {
    Remove-Item -Recurse -Force "artifacts"
}
New-Item -ItemType Directory -Path "artifacts/$artifactName" | Out-Null

Write-Host "Plugin: $PluginName"
Write-Host "Version: $Version"
Write-Host "Tag: $ReleaseTag"
Write-Host "Repository: $RepositorySlug"
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
Copy-Item "$PluginName/bin/Release/$targetFramework/$PluginName.dll" "artifacts/$artifactName/"

$ZipName = "$artifactName`_$Version.zip"
$ZipPath = Join-Path -Path "artifacts" -ChildPath $ZipName

Write-Host "Creating ZIP: $ZipName"
Compress-Archive -Path "artifacts/$artifactName" -DestinationPath $ZipPath -Force

# Guard 2: the built assembly version must equal the plugin version. Jellyfin
# reports PluginInfo.Version from the DLL assembly version and fetches the icon
# from /Plugins/<Id>/<PluginInfo.Version>/Image, so a mismatch ships a blank tile.
$builtDll = "artifacts/$artifactName/$PluginName.dll"
$asmVersion = [System.Reflection.AssemblyName]::GetAssemblyName((Resolve-Path $builtDll).Path).Version.ToString()
if ($asmVersion -ne $Version) {
    Write-Error "Assembly version mismatch - refusing to publish.`n  built assembly version: $asmVersion`n  plugin version: $Version"
    exit 1
}
Write-Host "Assembly version verified: $asmVersion"

if (Test-Path $ZipPath) {
    $size = (Get-Item $ZipPath).Length / 1KB
    Write-Host "ZIP created: $ZipName ($([Math]::Round($size, 2)) KB)"
    Write-Host ""

    # ── Phase 5: GitHub release ───────────────────────────────────────────────────
    # Check if a release already exists for this tag. If not, create it and upload
    # the zip. If it does exist, only upload if the asset is missing.

    # GitHub release handling (always enabled by default)
    $remoteTag = (git ls-remote --tags origin $ReleaseTag 2>$null)
    
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
    $title = "$PluginName $ReleaseTag"
    $notes = "Version $shortVer - $commitMsg"

    $assetUploadNeeded = $false
    
    if (-not $releaseExists) {
        Write-Host "Creating GitHub release '$ReleaseTag' and uploading asset."
        gh release create $ReleaseTag $ZipPath --repo $RepositorySlug --title $title --notes $notes 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create GitHub release for tag '$ReleaseTag'"
            exit 1
        }
        Write-Host "GitHub release created and asset uploaded."
        $assetUploadNeeded = $false
    } else {
        Write-Host "Release '$ReleaseTag' already exists; checking if asset upload is needed."
        $zipName = Split-Path $ZipPath -Leaf
        $assetNames = gh release view $ReleaseTag --repo $RepositorySlug --json assets --jq ".assets[].name" 2>$null
        if ($assetNames -notcontains $zipName) {
            Write-Host "Asset '$zipName' not present; uploading."
            gh release upload $ReleaseTag $ZipPath --repo $RepositorySlug 2>&1 | Write-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to upload asset to existing release '$ReleaseTag'"
                exit 1
            }
            Write-Host "Asset '$zipName' uploaded to release."
            $assetUploadNeeded = $false
        } else {
            Write-Host "Asset '$zipName' already present; skipping upload."
            Write-Host "WARNING: Skipping manifest update since asset is already on GitHub release."
            Write-Host "To update the manifest with a new version, create a new version tag and re-run the build."
            $assetUploadNeeded = $true
        }
    }

    # ── Phase 6: Update manifest.json ─────────────────────────────────────────────
    # Only update the manifest when we actually uploaded a new asset, so we don't
    # overwrite a previous release's checksum with stale data.

    # Only update manifest if we uploaded a new asset or created a new release
    if (-not $assetUploadNeeded) {
        Write-Host ""
        Write-Host "Updating manifest.json..."
        if (Test-Path "update-manifest.ps1") {
            & ./update-manifest.ps1 -Version $Version -ZipPath $ZipPath -ReleaseTag $ReleaseTag -RepositorySlug $RepositorySlug
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Manifest update script reported an error."
            } else {
                Write-Host "Manifest updated."
            }
        } else {
            Write-Warning "update-manifest.ps1 not found; skipping manifest update."
        }
    }
    
    Write-Host ""
    Write-Host "Build successful!"
    Write-Host "Location: $ZipPath"
} else {
    Write-Error "Failed to create ZIP file!"
    exit 1
}
