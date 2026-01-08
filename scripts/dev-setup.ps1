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

if (Test-Path "go.work") {
    Write-Host "✓ go.work already exists"
} else {
    Write-Host "Creating go.work..."
    go work init `
        ./cmd/morphir `
        ./pkg/bindings/wasm-componentmodel `
        ./pkg/config `
        ./pkg/models `
        ./pkg/pipeline `
        ./pkg/sdk `
        ./pkg/tooling `
        ./tests/bdd
    Write-Host "✓ Created go.work"
}

Write-Host "Syncing workspace..."
try {
    go work sync | Out-Null
    Write-Host "✓ Workspace synced successfully"
} catch {
    Write-Host "⚠ Workspace sync failed (this is normal if modules aren't tagged yet)"
    Write-Host "  The workspace will work for local development anyway"
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
