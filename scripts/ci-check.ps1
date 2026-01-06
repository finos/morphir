$ErrorActionPreference = "Stop"

mise run fmt-check
mise run verify
mise run test
mise run lint

Write-Host "✓ All CI checks passed!"
