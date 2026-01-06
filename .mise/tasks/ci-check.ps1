#MISE description="Run format, verify, test, and lint"
#MISE usage="mise run ci-check"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\ci-check.ps1") @Args
