#MISE description="Build the morphir-dev CLI"
#USAGE name build-dev.ps1
#USAGE bin build-dev.ps1
#USAGE about "Build the morphir-dev CLI"
#USAGE usage "mise run build-dev"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\build-dev.ps1") @Args
