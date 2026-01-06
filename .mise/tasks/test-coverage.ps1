#MISE description="Run tests with coverage reports"
#USAGE name test-coverage.ps1
#USAGE bin test-coverage.ps1
#USAGE about "Run tests with coverage reports"
#USAGE usage "mise run test-coverage"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\test-coverage.ps1") @Args
