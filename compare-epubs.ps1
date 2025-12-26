# Detailed EPUB analysis script
# Compares two EPUB files to find differences

param(
    [Parameter(Mandatory=$true)]
    [string]$EpubPath1,
    [Parameter(Mandatory=$true)]
    [string]$EpubPath2,
    [string]$Label1 = "File 1",
    [string]$Label2 = "File 2"
)

function Get-BinaryHash {
    param([string]$Path)
    $bufferSize = 16384
    $fileStream = [System.IO.File]::OpenRead($Path)
    $buffer = New-Object byte[] $bufferSize
    $bytesRead = $fileStream.Read($buffer, 0, $bufferSize)
    $fileStream.Close()
    
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = $md5.ComputeHash($buffer, 0, $bytesRead)
    return [System.BitConverter]::ToString($hash).Replace('-', '').ToLower()
}

function Get-FullFileHash {
    param([string]$Path)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $fileStream = [System.IO.File]::OpenRead($Path)
    $hash = $md5.ComputeHash($fileStream)
    $fileStream.Close()
    return [System.BitConverter]::ToString($hash).Replace('-', '').ToLower()
}

if (-not (Test-Path $EpubPath1)) { Write-Error "File not found: $EpubPath1"; exit 1 }
if (-not (Test-Path $EpubPath2)) { Write-Error "File not found: $EpubPath2"; exit 1 }

$file1 = Get-Item $EpubPath1
$file2 = Get-Item $EpubPath2

Write-Host "=== EPUB COMPARISON ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "$Label1: $($file1.FullName)"
Write-Host "  Size: $($file1.Length) bytes"
Write-Host "  Binary MD5 (first 16KB): $(Get-BinaryHash $EpubPath1)"
Write-Host "  Full MD5: $(Get-FullFileHash $EpubPath1)"
Write-Host ""
Write-Host "$Label2: $($file2.FullName)"
Write-Host "  Size: $($file2.Length) bytes"
Write-Host "  Binary MD5 (first 16KB): $(Get-BinaryHash $EpubPath2)"
Write-Host "  Full MD5: $(Get-FullFileHash $EpubPath2)"
Write-Host ""

if ((Get-BinaryHash $EpubPath1) -eq (Get-BinaryHash $EpubPath2)) {
    Write-Host "✓ Binary hashes MATCH - Files are identical in first 16KB" -ForegroundColor Green
} else {
    Write-Host "✗ Binary hashes DO NOT MATCH - Files are different" -ForegroundColor Red
    Write-Host "  This means the files have different content at the beginning"
    Write-Host "  This could indicate different editions or modifications"
}

if ((Get-FullFileHash $EpubPath1) -eq (Get-FullFileHash $EpubPath2)) {
    Write-Host "✓ Full file hashes MATCH - Files are identical" -ForegroundColor Green
} else {
    Write-Host "✗ Full file hashes DO NOT MATCH - Files are completely different" -ForegroundColor Red
}

Write-Host ""
Write-Host "Size difference: $([Math]::Abs($file1.Length - $file2.Length)) bytes"
if ($file1.Length -eq $file2.Length) {
    Write-Host "  Files are the same size"
} else {
    Write-Host "  Files are DIFFERENT sizes - likely different editions"
}
