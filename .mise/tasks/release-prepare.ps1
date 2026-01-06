#MISE description="Prepare release tags"
#USAGE name release-prepare.ps1
#USAGE bin release-prepare.ps1
#USAGE about "Prepare release tags"
#USAGE usage "mise run release-prepare -- vX.Y.Z"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\release-prepare.ps1") @Args
