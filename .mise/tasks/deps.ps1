#MISE description="Download Go module dependencies"
#MISE usage="mise run deps"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\deps.ps1") @Args
