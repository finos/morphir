#MISE description="Run morphir-dev CLI"
#MISE usage="mise run run-dev"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\run-dev.ps1") @Args
