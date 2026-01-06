# Description: Run tests with JUnit XML output
# Usage: mise run test-junit

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\test-junit.ps1") @Args
