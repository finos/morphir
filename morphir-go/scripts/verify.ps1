# Verify all modules build successfully

$ErrorActionPreference = "Stop"

Write-Host "Verifying all modules build..."

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptPath
Set-Location $repoRoot

$modules = @(
    "cmd/morphir",
    "pkg/models",
    "pkg/tooling",
    "pkg/sdk",
    "pkg/pipeline"
)

foreach ($module in $modules) {
    Write-Host "Building $module..."
    go build "./$module"
}

Write-Host "All modules build successfully!" -ForegroundColor Green
