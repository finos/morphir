#MISE description="Test external consumption without go.work"
#USAGE name test-external.ps1
#USAGE bin test-external.ps1
#USAGE about "Test external consumption without go.work"
#USAGE usage "mise run test-external"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\test-external.ps1") @Args
