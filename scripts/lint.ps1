$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "sync-changelog.ps1")

Write-Host "Running linters..."
if (-not (Get-Command golangci-lint -ErrorAction SilentlyContinue)) {
    Write-Host "golangci-lint not found. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"
    exit 1
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
    Write-Host "Linting $module..."
    Push-Location $module
    try {
        golangci-lint run --timeout=5m
    } finally {
        Pop-Location
    }
}
