#MISE description="Run all Go tests"
#USAGE name test.ps1
#USAGE bin test.ps1
#USAGE about "Run all Go tests"
#USAGE usage "mise run test"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\test.ps1") @Args
