# Description: Generate go.work for all modules
# Usage: mise run setup-workspace

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\setup-workspace.ps1") @Args
