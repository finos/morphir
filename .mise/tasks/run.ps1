# Description: Run morphir CLI
# Usage: mise run run

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\run.ps1") @Args
