$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path (Join-Path $scriptDir "link-skills.ps1")) {
    try {
        & (Join-Path $scriptDir "link-skills.ps1")
    } catch {
        Write-Host "Warning: link-skills failed; continuing." -ForegroundColor DarkGray
    }
}

Write-Host "Setting up Go workspace for local development..."

$setupWorkspace = Join-Path $scriptDir "setup-workspace.ps1"
if (Test-Path $setupWorkspace) {
    & $setupWorkspace
} else {
    Write-Host "❌ Missing setup-workspace.ps1; cannot configure go.work automatically" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ Development environment ready!"
Write-Host ""
Write-Host "The go.work file enables you to make changes across modules locally"
Write-Host "without needing replace directives or version tags."
Write-Host ""
Write-Host "Note: If you see 'unknown revision' errors, that's expected until"
Write-Host "      modules are tagged. Local development will still work."
Write-Host ""
Write-Host "To verify your setup, run:"
Write-Host "  mise run verify"
Write-Host ""
