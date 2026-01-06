$ErrorActionPreference = "Stop"

Write-Host "Downloading dependencies..."
go work sync
go mod download ./...
