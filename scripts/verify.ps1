# Verify all modules build successfully

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "sync-changelog.ps1")

Write-Host "Verifying all modules build..."

$repoRoot = Split-Path -Parent $scriptDir
Set-Location $repoRoot

if (-not (Test-Path "go.work")) {
    & (Join-Path $scriptDir "setup-workspace.ps1")
}

$modules = @(
    "cmd/morphir",
    "pkg/bindings/wasm-componentmodel",
    "pkg/models",
    "pkg/tooling",
    "pkg/sdk",
    "pkg/pipeline"
)

foreach ($module in $modules) {
    Write-Host "Building $module..."
    Push-Location $module
    try {
        go build ./...
    } finally {
        Pop-Location
    }
}

Write-Host "All modules build successfully!" -ForegroundColor Green
