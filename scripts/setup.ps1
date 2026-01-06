$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path (Join-Path $scriptDir "dev-setup.ps1")) {
    & (Join-Path $scriptDir "dev-setup.ps1")
}

Write-Host "Setting up development environment..."
Write-Host "1. Installing npm dependencies (for git hooks)..."
if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm install
} else {
    Write-Host "Warning: npm not found. Git hooks will not be installed."
    Write-Host "Install Node.js from https://nodejs.org/ to enable git hooks."
}

Write-Host "2. Verifying git hooks are installed..."
if (Test-Path ".husky/pre-push") {
    Write-Host "   ✓ Git hooks installed successfully"
} else {
    Write-Host "   ⚠ Git hooks not installed (npm install may have failed)"
}

Write-Host ""
Write-Host "Development environment setup complete!"
Write-Host "Run 'mise run build-dev' to build the development version."
