# Description: Install morphir-dev to Go bin
# Usage: mise run install-dev

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\install-dev.ps1") @Args
