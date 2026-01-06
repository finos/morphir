#MISE description="Run release automation"
#MISE usage="mise run release -- vX.Y.Z"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\release.ps1") @Args
