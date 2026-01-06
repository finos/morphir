#MISE description="Set up local Go workspace"
#USAGE name dev-setup.ps1
#USAGE bin dev-setup.ps1
#USAGE about "Set up local Go workspace"
#USAGE usage "mise run dev-setup"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\dev-setup.ps1") @Args
