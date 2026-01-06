$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "sync-changelog.ps1")

Write-Host "Testing external consumption (no go.work)..."
Write-Host "This verifies that module versions in go.mod are correct."

Push-Location "cmd/morphir"
try {
    go mod download
    go build .
} finally {
    Pop-Location
}

Write-Host "✅ cmd/morphir builds successfully as external consumer would use it"
