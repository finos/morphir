$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "sync-changelog.ps1")

Write-Host "Running tests..."
$modules = @(
    "cmd/morphir",
    "pkg/bindings/wasm-componentmodel",
    "pkg/models",
    "pkg/tooling",
    "pkg/sdk",
    "pkg/pipeline"
)

foreach ($module in $modules) {
    if (Test-Path $module) {
        Write-Host "Testing $module..."
        Push-Location $module
        try {
            go test ./...
        } finally {
            Pop-Location
        }
    }
}
