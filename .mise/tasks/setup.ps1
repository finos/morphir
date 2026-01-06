#MISE description="Run full dev environment setup"
#USAGE name setup.ps1
#USAGE bin setup.ps1
#USAGE about "Run full dev environment setup"
#USAGE usage "mise run setup"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\setup.ps1") @Args
