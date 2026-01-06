# Install morphir-dev to the Go bin directory

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptPath
$binary = Join-Path $repoRoot "bin\morphir-dev.exe"

if (Test-Path (Join-Path $scriptPath "build-dev.ps1")) {
    & (Join-Path $scriptPath "build-dev.ps1")
}

if (-not (Test-Path $binary)) {
    Write-Host "Error: morphir-dev binary not found at $binary" -ForegroundColor Red
    Write-Host "Please run 'mise run build-dev' first" -ForegroundColor Red
    exit 1
}

# Get Go environment variables
$gopath = (go env GOPATH).Trim()
$gobin = (go env GOBIN).Trim()

# Determine target directory
if ($gobin -and $gobin -ne "") {
    $targetDir = $gobin
} else {
    $targetDir = Join-Path $gopath "bin"
}

# Create target directory if it doesn't exist
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}

# Copy binary
$targetPath = Join-Path $targetDir "morphir-dev.exe"
Copy-Item $binary $targetPath -Force

Write-Host "Installed to $targetPath" -ForegroundColor Green
