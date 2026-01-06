# Description: Build the morphir-dev CLI
# Usage: mise run build-dev

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\build-dev.ps1") @Args
