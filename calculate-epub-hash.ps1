# Script to calculate the binary MD5 hash of EPUB files (partial MD5 like KOReader does)
# This helps diagnose file mismatch issues

# KOReader uses a partial MD5 algorithm that samples the file at exponential intervals:
# - Samples at: 256B, 1KB, 4KB, 16KB, 64KB, 256KB, 1MB, 4MB, 16MB, 64MB, 1GB
# - Each sample is 1KB (1024 bytes)
# - Position formula: 1024 * 4^i (for i = -1 to 10)

param(
    [Parameter(Mandatory=$true, HelpMessage="Path to the EPUB file")]
    [string]$EpubPath
)

if (-not (Test-Path $EpubPath)) {
    Write-Error "File not found: $EpubPath"
    exit 1
}

$file = Get-Item $EpubPath
Write-Host "Calculating partial MD5 hash for: $($file.FullName)"
Write-Host "File size: $($file.Length) bytes"
Write-Host ""

# Open file and calculate partial MD5
$fileStream = [System.IO.File]::OpenRead($EpubPath)
$md5 = [System.Security.Cryptography.MD5]::Create()
$step = 1024
$chunkSize = 1024

Write-Host "Sampling at positions (KOReader partial MD5 algorithm):"

# Loop through exponential positions: i = -1 to 10
# Position = 1024 * 4^i
for ($i = -1; $i -le 10; $i++) {
    $position = $step * [Math]::Pow(4, $i)
    
    # Stop if position exceeds file size
    if ($position -ge $fileStream.Length) {
        Write-Host "  Position $([long]$position) exceeds file size - stopping"
        break
    }
    
    # Seek to position
    $fileStream.Seek([long]$position, [System.IO.SeekOrigin]::Begin) | Out-Null
    
    # Read 1KB from this position
    $buffer = New-Object byte[] $chunkSize
    $bytesRead = $fileStream.Read($buffer, 0, $chunkSize)
    
    if ($bytesRead -gt 0) {
        $md5.TransformBlock($buffer, 0, $bytesRead, $null, 0)
        Write-Host "  Position $([long]$position): Read $bytesRead bytes"
    } else {
        Write-Host "  Position $([long]$position): EOF - stopping"
        break
    }
}

$fileStream.Close()

# Finalize hash
$md5.TransformFinalBlock([byte[]]@(), 0, 0) | Out-Null
$hash = $md5.Hash
$hashString = [System.BitConverter]::ToString($hash).Replace('-', '').ToLower()

Write-Host ""
Write-Host "Partial MD5 Hash (KOReader method):"
Write-Host $hashString
Write-Host ""
Write-Host "To verify this file matches KOReader, compare this hash to the document ID shown in:"
Write-Host "- Jellyfin logs when syncing"
Write-Host "- The warning message: 'Searching through XXX items for document ID ""<hash>""'"

