#MISE description="Run all Go tests"
#MISE usage="mise run test"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\test.ps1") @Args
