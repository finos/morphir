$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "sync-changelog.ps1")

Write-Host "Checking workspace..."
& (Join-Path $scriptDir "workspace-doctor.ps1") -Fix replace

if (-not (Test-Path "bin")) {
    New-Item -ItemType Directory -Path "bin" | Out-Null
}

go build -o bin/morphir.exe ./cmd/morphir
