#MISE description="Install morphir-dev to Go bin"
#USAGE name install-dev.ps1
#USAGE bin install-dev.ps1
#USAGE about "Install morphir-dev to Go bin"
#USAGE usage "mise run install-dev"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\install-dev.ps1") @Args
