#MISE description="Run tests with JUnit XML output"
#USAGE name test-junit.ps1
#USAGE bin test-junit.ps1
#USAGE about "Run tests with JUnit XML output"
#USAGE usage "mise run test-junit"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\test-junit.ps1") @Args
