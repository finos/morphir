# Description: Run golangci-lint
# Usage: mise run lint

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\lint.ps1") @Args
