# Description: Prepare release tags
# Usage: mise run release-prepare -- vX.Y.Z

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\release-prepare.ps1") @Args
