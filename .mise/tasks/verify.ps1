#MISE description="Verify all modules build"
#MISE usage="mise run verify"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\verify.ps1") @Args
