# Description: Clean build artifacts
# Usage: mise run clean

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\clean.ps1") @Args
