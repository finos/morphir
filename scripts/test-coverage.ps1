$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "sync-changelog.ps1")

Write-Host "Running tests with coverage..."

$repoRoot = (Get-Location).Path
$coverageDir = Join-Path $repoRoot "coverage"
New-Item -ItemType Directory -Force -Path $coverageDir | Out-Null

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
        Write-Host "Testing $module with coverage..."
        $moduleName = Split-Path $module -Leaf
        Push-Location $module
        try {
            $profilePath = Join-Path $coverageDir "${moduleName}.out"
            go test -coverprofile="$profilePath" -covermode=atomic ./...
        } finally {
            Pop-Location
        }
    }
}

Write-Host "Merging coverage profiles..."
$mergedCoverage = Join-Path $repoRoot "coverage.out"
"mode: atomic" | Set-Content -Path $mergedCoverage
Get-ChildItem -Path $coverageDir -Filter "*.out" | ForEach-Object {
    Get-Content $_.FullName | Where-Object { $_ -notmatch "^mode:" } | Add-Content -Path $mergedCoverage
}

Write-Host ""
Write-Host "Coverage Summary:"
(go tool cover -func=coverage.out | Select-Object -Last 1) | Write-Host

Write-Host ""
Write-Host "Coverage report generated: coverage.out"
Write-Host "View HTML report: go tool cover -html=coverage.out"
