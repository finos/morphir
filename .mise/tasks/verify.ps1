#MISE description="Verify all modules build"
#USAGE name verify.ps1
#USAGE bin verify.ps1
#USAGE about "Verify all modules build"
#USAGE usage "mise run verify"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\verify.ps1") @Args
