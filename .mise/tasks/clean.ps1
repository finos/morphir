#MISE description="Clean build artifacts"
#MISE usage="mise run clean"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\clean.ps1") @Args
