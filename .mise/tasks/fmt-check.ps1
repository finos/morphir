#MISE description="Check Go formatting"
#MISE usage="mise run fmt-check"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\fmt-check.ps1") @Args
