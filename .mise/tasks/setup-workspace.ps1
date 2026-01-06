#MISE description="Generate go.work for all modules"
#MISE usage="mise run setup-workspace"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\setup-workspace.ps1") @Args
