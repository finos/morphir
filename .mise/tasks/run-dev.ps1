#MISE description="Run morphir-dev CLI"
#USAGE name run-dev.ps1
#USAGE bin run-dev.ps1
#USAGE about "Run morphir-dev CLI"
#USAGE usage "mise run run-dev"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\run-dev.ps1") @Args
