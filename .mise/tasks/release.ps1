#MISE description="Run release automation"
#USAGE name release.ps1
#USAGE bin release.ps1
#USAGE about "Run release automation"
#USAGE usage "mise run release -- vX.Y.Z"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\release.ps1") @Args
