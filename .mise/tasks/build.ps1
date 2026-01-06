#MISE description="Build the morphir CLI"
#USAGE name build.ps1
#USAGE bin build.ps1
#USAGE about "Build the morphir CLI"
#USAGE usage "mise run build"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\build.ps1") @Args
