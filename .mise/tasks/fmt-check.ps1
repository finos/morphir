#MISE description="Check Go formatting"
#USAGE name fmt-check.ps1
#USAGE bin fmt-check.ps1
#USAGE about "Check Go formatting"
#USAGE usage "mise run fmt-check"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\fmt-check.ps1") @Args
