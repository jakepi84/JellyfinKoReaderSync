param(
    [string]$Version,
    [string]$ZipPath,
    [string]$ReleaseTag,
    [string]$RepositorySlug
)

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

$RepositoryUrl = "https://github.com/$RepositorySlug"

if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Error "Version is required"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ZipPath) -or -not (Test-Path $ZipPath)) {
    Write-Error "ZIP file not found: $ZipPath"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    $parts = $Version.Split('.')
    $ReleaseTag = "v$($parts[0]).$($parts[1]).$($parts[2])"
}

Write-Host "Updating manifest.json"
Write-Host "====================="
Write-Host ""
Write-Host "Version: $Version"
Write-Host "Tag: $ReleaseTag"
Write-Host "ZIP: $ZipPath"
Write-Host ""

if (-not (Test-Path "manifest.json")) {
    Write-Error "manifest.json not found!"
    exit 1
}

$manifestArray = Get-Content "manifest.json" -Raw | ConvertFrom-Json

# Ensure it's an array
if ($manifestArray -isnot [Array]) {
    $manifestArray = @($manifestArray)
}

$md5 = New-Object System.Security.Cryptography.MD5CryptoServiceProvider
$hash = $md5.ComputeHash([System.IO.File]::ReadAllBytes((Resolve-Path $ZipPath)))
$checksum = [System.BitConverter]::ToString($hash).Replace("-", "").ToLower()

Write-Host "Checksum: $checksum"

$buildYaml = if (Test-Path "build.yaml") { Get-Content "build.yaml" -Raw } else { $null }
$targetAbi = if ($buildYaml -and ($buildYaml -match 'targetAbi:\s*"?([^"\n]+)"?')) { $matches[1] } else { "10.10.0.0" }

# Build changelog from latest commit message; fallback to build.yaml or default
$changelog = $null
$commitMessage = $null
try {
    $commitMessage = git log -1 --pretty=%B 2>$null
} catch { $commitMessage = $null }

if (-not [string]::IsNullOrWhiteSpace($commitMessage)) {
    $cleanCommit = ($commitMessage.Trim())
    # Optionally prefix with human-friendly version (major.minor.patch)
    $verParts = $Version.Split('.')
    $shortVer = if ($verParts.Length -ge 3) { "$($verParts[0]).$($verParts[1]).$($verParts[2])" } else { $Version }
    $changelog = "Version $shortVer - $cleanCommit"
} elseif ($buildYaml -and ($buildYaml -match 'changelog:\s*>?\s*(.+?)(?=^[a-z]|$)')) {
    $changelog = $matches[1].Trim()
} else {
    $changelog = "Release version $Version"
}

Write-Host "TargetAbi: $targetAbi"
Write-Host "Changelog: $changelog"

$zipFileName = Split-Path $ZipPath -Leaf
$sourceUrl = "$RepositoryUrl/releases/download/$ReleaseTag/$zipFileName"
Write-Host "SourceUrl: $sourceUrl"
Write-Host ""

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$newVersion = [PSCustomObject]@{
    version = $Version
    changelog = $changelog
    targetAbi = $targetAbi
    sourceUrl = $sourceUrl
    checksum = $checksum
    timestamp = $timestamp
}

# Update the first package's versions array
$package = $manifestArray[0]

# If an existing entry matches the new one (excluding timestamp), skip update
$existingEntry = $package.versions | Where-Object { $_.version -eq $Version } | Select-Object -First 1
if ($existingEntry -and `
    $existingEntry.checksum -eq $checksum -and `
    $existingEntry.sourceUrl -eq $sourceUrl -and `
    $existingEntry.targetAbi -eq $targetAbi -and `
    $existingEntry.changelog -eq $changelog) {
    Write-Host "Manifest already up to date; no changes made."
    return
}

# Replace any existing entry for this version, otherwise prepend new
$existingVersions = $package.versions | Where-Object { $_.version -ne $Version }
$package.versions = @($newVersion) + $existingVersions

# Convert to JSON maintaining array structure
$json = ConvertTo-Json @($package) -Depth 10
Set-Content "manifest.json" $json -Encoding UTF8

Write-Host "Updated manifest.json"
Write-Host ""
Write-Host "New entry added:"
Write-Host "  Version: $($newVersion.version)"
Write-Host "  TargetAbi: $($newVersion.targetAbi)"
Write-Host "  Checksum: $($newVersion.checksum)"

