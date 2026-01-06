#MISE description="Download Go module dependencies"
#USAGE name deps.ps1
#USAGE bin deps.ps1
#USAGE about "Download Go module dependencies"
#USAGE usage "mise run deps"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\deps.ps1") @Args
