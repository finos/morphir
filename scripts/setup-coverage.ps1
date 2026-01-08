# setup-coverage.ps1 - Set up and verify code coverage for all Go modules
#
# This script:
# 1. Discovers all Go modules in the repository
# 2. Verifies each module can run tests with coverage
# 3. Reports any issues with coverage setup
# 4. Shows summary of all covered modules
#
# Usage:
#   .\scripts\setup-coverage.ps1           # Discover and verify all modules
#   .\scripts\setup-coverage.ps1 -Check    # Check only, don't run tests
#   .\scripts\setup-coverage.ps1 -List     # List all discoverable modules

param(
    [switch]$Check,
    [switch]$List
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

# Discover all Go modules (directories containing go.mod)
function Get-GoModules {
    Get-ChildItem -Path $repoRoot -Recurse -Name "go.mod" -File |
        Where-Object { $_ -notlike "*vendor*" -and $_ -notlike "*testdata*" } |
        ForEach-Object { Split-Path -Parent $_ } |
        Sort-Object -Unique
}

# Check if a module has any Go test files
function Test-HasTests {
    param([string]$ModulePath)
    $fullPath = Join-Path $repoRoot $ModulePath
    $testFiles = Get-ChildItem -Path $fullPath -Recurse -Name "*_test.go" -File -ErrorAction SilentlyContinue
    return $testFiles.Count -gt 0
}

# Check if a module can run tests
function Test-CanRunTests {
    param([string]$ModulePath)
    $fullPath = Join-Path $repoRoot $ModulePath
    Push-Location $fullPath
    try {
        $null = go test -c ./... -o $null 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
    finally {
        Pop-Location
    }
}

Write-Host "=== Morphir Code Coverage Setup ===" -ForegroundColor Blue
Write-Host ""

# Discover all modules
Write-Host "Discovering Go modules..." -ForegroundColor Blue
$modules = @(Get-GoModules)

if ($modules.Count -eq 0) {
    Write-Host "Error: No Go modules found in repository" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($modules.Count) Go modules" -ForegroundColor Green
Write-Host ""

# List only mode
if ($List) {
    Write-Host "All discoverable modules:" -ForegroundColor Blue
    foreach ($module in $modules) {
        Write-Host "  - $module"
    }
    exit 0
}

# Categorize modules
$testableModules = @()
$noTestModules = @()
$failedModules = @()

Write-Host "Analyzing modules..." -ForegroundColor Blue
foreach ($module in $modules) {
    if (Test-HasTests $module) {
        if (-not $Check) {
            if (Test-CanRunTests $module) {
                $testableModules += $module
                Write-Host "  [OK] $module" -ForegroundColor Green
            }
            else {
                $failedModules += $module
                Write-Host "  [FAIL] $module (test compilation failed)" -ForegroundColor Red
            }
        }
        else {
            $testableModules += $module
            Write-Host "  [OK] $module (has tests)" -ForegroundColor Green
        }
    }
    else {
        $noTestModules += $module
        Write-Host "  [SKIP] $module (no tests)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Blue
Write-Host "  Testable modules:      $($testableModules.Count)" -ForegroundColor Green
Write-Host "  Modules without tests: $($noTestModules.Count)" -ForegroundColor Yellow
if ($failedModules.Count -gt 0) {
    Write-Host "  Failed modules:        $($failedModules.Count)" -ForegroundColor Red
}

# Generate MODULES array for scripts
Write-Host ""
Write-Host "=== MODULES array for scripts ===" -ForegroundColor Blue
Write-Host "Copy this to scripts/test-junit.sh and scripts/test-coverage.sh:"
Write-Host ""
Write-Host "MODULES=("
foreach ($module in $testableModules) {
    Write-Host "    `"$module`""
}
Write-Host ")"

# Run quick coverage test if not check-only
if (-not $Check -and $testableModules.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Running coverage verification ===" -ForegroundColor Blue

    $coverageDir = Join-Path $repoRoot "coverage"
    New-Item -ItemType Directory -Force -Path $coverageDir | Out-Null

    $passed = 0
    $failed = 0

    foreach ($module in $testableModules) {
        $moduleName = Split-Path -Leaf $module
        Write-Host "  Testing $module... " -NoNewline

        Push-Location (Join-Path $repoRoot $module)
        try {
            $coverFile = Join-Path $coverageDir "$moduleName.out"
            $null = go test -coverprofile=$coverFile -covermode=atomic ./... 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "OK" -ForegroundColor Green
                $passed++
            }
            else {
                Write-Host "FAILED" -ForegroundColor Red
                $failed++
            }
        }
        catch {
            Write-Host "FAILED" -ForegroundColor Red
            $failed++
        }
        finally {
            Pop-Location
        }
    }

    Write-Host ""
    Write-Host "=== Coverage Verification Results ===" -ForegroundColor Blue
    Write-Host "  Passed: $passed" -ForegroundColor Green
    if ($failed -gt 0) {
        Write-Host "  Failed: $failed" -ForegroundColor Red
    }

    # Merge coverage
    if ($passed -gt 0) {
        Write-Host ""
        Write-Host "Merging coverage profiles..." -ForegroundColor Blue
        Push-Location $repoRoot
        try {
            "mode: atomic" | Out-File -FilePath "coverage.out" -Encoding utf8
            Get-ChildItem -Path $coverageDir -Filter "*.out" | ForEach-Object {
                Get-Content $_.FullName | Where-Object { $_ -notmatch "^mode:" } | Add-Content "coverage.out"
            }

            Write-Host ""
            Write-Host "Coverage Summary:" -ForegroundColor Blue
            go tool cover -func=coverage.out | Select-Object -Last 1
        }
        finally {
            Pop-Location
        }
    }
}

# Show next steps
Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Blue
if ($noTestModules.Count -gt 0) {
    Write-Host "  1. Consider adding tests to modules without test coverage:"
    foreach ($module in $noTestModules) {
        Write-Host "     - $module"
    }
}
if ($failedModules.Count -gt 0) {
    Write-Host "  2. Fix test compilation issues in:"
    foreach ($module in $failedModules) {
        Write-Host "     - $module"
    }
}
Write-Host ""
Write-Host "  To view detailed coverage:"
Write-Host "    go tool cover -html=coverage.out"
Write-Host ""
Write-Host "  To run full coverage with JUnit reports:"
Write-Host "    mise run test-junit"
