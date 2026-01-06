#MISE description="Run morphir CLI"
#USAGE name run.ps1
#USAGE bin run.ps1
#USAGE about "Run morphir CLI"
#USAGE usage "mise run run"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\run.ps1") @Args
