#MISE description="Build the morphir-dev CLI"
#MISE usage="mise run build-dev"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\build-dev.ps1") @Args
