param(
    [string]$Version,
    [string]$ReleaseTag
)

Write-Host ""
Write-Host "KOReader Sync Release Builder"
Write-Host "============================="
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

Write-Host "STEP 1: Building Release"
Write-Host "========================"
Write-Host ""
& ".\build-release.ps1" -Version $Version -ReleaseTag $ReleaseTag
if ($LASTEXITCODE -ne 0) {
    exit 1
}

Write-Host ""
Write-Host "STEP 2: Updating Manifest"
Write-Host "========================="
Write-Host ""
$ZipPath = "artifacts/jellyfin-koreader-sync_$Version.zip"
& ".\update-manifest.ps1" -Version $Version -ZipPath $ZipPath -ReleaseTag $ReleaseTag
if ($LASTEXITCODE -ne 0) {
    exit 1
}

Write-Host ""
Write-Host "STEP 3: Ready for Git Operations"
Write-Host "=================================="
Write-Host ""

Write-Host "Manifest updated: manifest.json"
Write-Host ""
Write-Host "Changes ready to commit:"
Write-Host "  git add manifest.json"
Write-Host "  git commit -m 'Update manifest for version $Version'"
Write-Host "  git push origin main"
Write-Host ""

# Check if GITHUB_TOKEN is set for upload
$ghToken = $env:GITHUB_TOKEN
if ([string]::IsNullOrWhiteSpace($ghToken)) {
    Write-Host "Skipping ZIP upload (GITHUB_TOKEN not set)"
    Write-Host ""
    Write-Host "To upload the ZIP later, set the token and run:"
    Write-Host "  `$env:GITHUB_TOKEN = 'your_token_here'"
    Write-Host "  .\upload-release.ps1 -Version $Version -ReleaseTag $ReleaseTag"
} else {
    Write-Host "Uploading ZIP to GitHub release..."
    Write-Host ""
    
    $zipName = Split-Path $ZipPath -Leaf
    $zipFile = Resolve-Path $ZipPath
    
    # Get release ID
    $releaseUrl = "https://api.github.com/repos/jakepi84/JellyfinKoReaderSync/releases/tags/$ReleaseTag"
    
    Write-Host "Getting release ID for $ReleaseTag..."
    $releaseResponse = Invoke-RestMethod -Uri $releaseUrl -Headers @{ Authorization = "Bearer $ghToken" } -ErrorAction Stop
    $releaseId = $releaseResponse.id
    
    if ([string]::IsNullOrWhiteSpace($releaseId)) {
        Write-Error "Could not find release for tag $ReleaseTag"
        exit 1
    }
    
    Write-Host "Uploading $zipName..."
    $uploadUri = "https://uploads.github.com/repos/jakepi84/JellyfinKoReaderSync/releases/$releaseId/assets?name=$zipName"
    
    $fileBytes = [System.IO.File]::ReadAllBytes($zipFile)
    $response = Invoke-RestMethod -Uri $uploadUri `
        -Method POST `
        -Headers @{ 
            Authorization = "Bearer $ghToken"
            "Content-Type" = "application/octet-stream"
        } `
        -Body $fileBytes -ErrorAction Stop
    
    if ($response.state -eq "uploaded") {
        Write-Host "ZIP uploaded successfully!"
    } else {
        Write-Host "Upload response: $($response | ConvertTo-Json)"
    }
    Write-Host ""
}

Write-Host "SUCCESS!"
Write-Host "========"
Write-Host ""
Write-Host "Release preparation complete!"
Write-Host "ZIP location: $ZipPath"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Review manifest.json changes"
Write-Host "2. Commit and push:"
Write-Host "   git add manifest.json"
Write-Host "   git commit -m 'Update manifest for version $Version'"
Write-Host "   git push origin main"
Write-Host ""
