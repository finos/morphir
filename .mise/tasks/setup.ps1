#MISE description="Run full dev environment setup"
#MISE usage="mise run setup"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\setup.ps1") @Args
