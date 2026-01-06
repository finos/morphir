#MISE description="Build a release snapshot"
#USAGE name release-snapshot.ps1
#USAGE bin release-snapshot.ps1
#USAGE about "Build a release snapshot"
#USAGE usage "mise run release-snapshot"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\release-snapshot.ps1") @Args
