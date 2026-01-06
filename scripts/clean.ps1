$ErrorActionPreference = "Stop"

Write-Host "Cleaning build artifacts..."
if (Test-Path "bin") {
    Remove-Item -Recurse -Force "bin"
}

go clean ./...
