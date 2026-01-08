$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

& (Join-Path $scriptDir "sync-changelog.ps1")

Write-Host "Running tests with coverage..."

$coverageDir = Join-Path $repoRoot "coverage"
New-Item -ItemType Directory -Force -Path $coverageDir | Out-Null

# Dynamically discover all Go modules with tests
function Get-TestableModules {
    Get-ChildItem -Path $repoRoot -Recurse -Name "go.mod" -File |
        Where-Object { $_ -notlike "*vendor*" -and $_ -notlike "*testdata*" } |
        ForEach-Object {
            $modulePath = Split-Path -Parent $_
            $fullPath = Join-Path $repoRoot $modulePath
            $testFiles = Get-ChildItem -Path $fullPath -Recurse -Name "*_test.go" -File -ErrorAction SilentlyContinue
            if ($testFiles.Count -gt 0) {
                $modulePath
            }
        } |
        Sort-Object -Unique
}

Write-Host "Discovering Go modules with tests..."
$modules = @(Get-TestableModules)
Write-Host "Found $($modules.Count) testable modules"
Write-Host ""

foreach ($module in $modules) {
    $fullPath = Join-Path $repoRoot $module
    if (Test-Path $fullPath) {
        Write-Host "Testing $module with coverage..."
        $moduleName = Split-Path $module -Leaf
        Push-Location $fullPath
        try {
            $profilePath = Join-Path $coverageDir "${moduleName}.out"
            go test -coverprofile="$profilePath" -covermode=atomic ./...
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
Write-Host "Coverage Summary:"
(go tool cover -func=$mergedCoverage | Select-Object -Last 1) | Write-Host

Write-Host ""
Write-Host "Coverage report generated: coverage.out"
Write-Host "View HTML report: go tool cover -html=coverage.out"
