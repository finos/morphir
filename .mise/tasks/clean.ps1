#MISE description="Clean build artifacts"
#USAGE name clean.ps1
#USAGE bin clean.ps1
#USAGE about "Clean build artifacts"
#USAGE usage "mise run clean"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\clean.ps1") @Args
