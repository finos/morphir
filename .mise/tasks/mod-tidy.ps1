#MISE description="Run go mod tidy for all modules"
#USAGE name mod-tidy.ps1
#USAGE bin mod-tidy.ps1
#USAGE about "Run go mod tidy for all modules"
#USAGE usage "mise run mod-tidy"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\mod-tidy.ps1") @Args
