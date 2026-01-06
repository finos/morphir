#MISE description="Run format, verify, test, and lint"
#USAGE name ci-check.ps1
#USAGE bin ci-check.ps1
#USAGE about "Run format, verify, test, and lint"
#USAGE usage "mise run ci-check"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\ci-check.ps1") @Args
