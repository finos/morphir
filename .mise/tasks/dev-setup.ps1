# Description: Set up local Go workspace
# Usage: mise run dev-setup

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\dev-setup.ps1") @Args
