param(
    [string]$Version,
    [string]$ReleaseTag,
    [string]$PluginName,
    [string]$RepositorySlug,
    [switch]$AutoTag
)

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

$artifactName = $PluginName -replace 'Jellyfin\.Plugin\.', 'jellyfin-' | ForEach-Object { $_.ToLower() }

Write-Host ""
Write-Host "$PluginName Release Builder"
Write-Host "$("=" * ($PluginName.Length + 16))"
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
        Write-Host "Latest tag: $latestTag"
    } else {
        Write-Error "Could not get latest git tag. Ensure git is configured and tags exist."
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    $ReleaseTag = "v$($Version.Substring(0, $Version.LastIndexOf('.')))"
}

Write-Host "Building, packaging, and uploading release..."
Write-Host ""

& ".\build-release.ps1" `
    -Version $Version `
    -ReleaseTag $ReleaseTag `
    -PluginName $PluginName `
    -RepositorySlug $RepositorySlug `
    -AutoTag:$AutoTag `
    -CreateGitHubRelease
if ($LASTEXITCODE -ne 0) {
    exit 1
}

Write-Host ""
Write-Host "SUCCESS!"
Write-Host "========"
Write-Host ""
Write-Host "Release complete for $PluginName v$Version"
Write-Host "ZIP location: artifacts\$artifactName`_$Version.zip"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Review manifest.json changes"
Write-Host "2. Commit and push:"
Write-Host "   git add manifest.json"
Write-Host "   git commit -m 'Update manifest for version $Version'"
Write-Host "   git push origin main"
Write-Host ""
