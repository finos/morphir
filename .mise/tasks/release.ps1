# Description: Run release automation
# Usage: mise run release -- vX.Y.Z

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\release.ps1") @Args
