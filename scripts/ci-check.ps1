# CI check script - runs all checks that should pass in CI

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptPath
Set-Location $repoRoot

Write-Host "Running CI checks..."

# Format check
Write-Host "Checking code formatting..."
$formatOutput = go fmt ./...
if ($formatOutput) {
    Write-Host "✗ Code formatting issues found. Run 'just fmt' to fix." -ForegroundColor Red
    exit 1
} else {
    Write-Host "✓ Code is properly formatted" -ForegroundColor Green
}

# Build verification
Write-Host "Verifying all modules build..."
& (Join-Path $scriptPath "verify.ps1")

# Run tests
Write-Host "Running tests..."
go test ./...

# Lint check (if available)
if (Get-Command golangci-lint -ErrorAction SilentlyContinue) {
    Write-Host "Running linters..."
    golangci-lint run ./...
    Write-Host "✓ Linting passed" -ForegroundColor Green
} else {
    Write-Host "⚠ golangci-lint not found, skipping lint check" -ForegroundColor Yellow
}

Write-Host "✓ All CI checks passed!" -ForegroundColor Green
