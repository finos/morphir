#MISE description="Run golangci-lint"
#USAGE name lint.ps1
#USAGE bin lint.ps1
#USAGE about "Run golangci-lint"
#USAGE usage "mise run lint"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\lint.ps1") @Args
