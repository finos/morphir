$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "sync-changelog.ps1")

Write-Host "Running tests with JUnit XML output..."

if (-not (Get-Command gotestsum -ErrorAction SilentlyContinue)) {
    Write-Host "Installing gotestsum..."
    go install gotest.tools/gotestsum@latest
}

$repoRoot = (Get-Location).Path
$testResults = Join-Path $repoRoot "test-results"
$coverageDir = Join-Path $repoRoot "coverage"
New-Item -ItemType Directory -Force -Path $testResults | Out-Null
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
        Write-Host "Testing $module..."
        $moduleName = Split-Path $module -Leaf
        $junitPath = Join-Path $testResults "${moduleName}.xml"
        $coveragePath = Join-Path $coverageDir "${moduleName}.out"
        Push-Location $module
        try {
            gotestsum --junitfile="$junitPath" --format=testname -- -coverprofile="$coveragePath" -covermode=atomic ./...
        } finally {
            Pop-Location
        }
    }
}

Write-Host ""
Write-Host "Merging coverage profiles..."
$mergedCoverage = Join-Path $repoRoot "coverage.out"
"mode: atomic" | Set-Content -Path $mergedCoverage
Get-ChildItem -Path $coverageDir -Filter "*.out" | ForEach-Object {
    Get-Content $_.FullName | Where-Object { $_ -notmatch "^mode:" } | Add-Content -Path $mergedCoverage
}

Write-Host ""
Write-Host "Test results generated in test-results/"
Write-Host "Coverage profiles generated in coverage/"
Write-Host "Merged coverage: coverage.out"
