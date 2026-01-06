$ErrorActionPreference = "Stop"

Write-Host "Formatting Go code..."
go fmt ./...
