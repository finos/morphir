# Run go mod tidy for all modules in the monorepo

$ErrorActionPreference = "Stop"

Write-Host "Running go mod tidy for all modules..."

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptPath
Set-Location $repoRoot

$modules = @(
    "cmd/morphir",
    "pkg/bindings/wasm-componentmodel",
    "pkg/models",
    "pkg/tooling",
    "pkg/sdk",
    "pkg/pipeline"
)

foreach ($module in $modules) {
    Write-Host "Running go mod tidy in $module..."
    Push-Location $module
    go mod tidy
    Pop-Location
}

Write-Host "All modules tidied successfully!"
