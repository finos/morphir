#MISE description="Generate go.work for all modules"
#USAGE name setup-workspace.ps1
#USAGE bin setup-workspace.ps1
#USAGE about "Generate go.work for all modules"
#USAGE usage "mise run setup-workspace"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\setup-workspace.ps1") @Args
