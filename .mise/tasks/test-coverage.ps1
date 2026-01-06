# Description: Run tests with coverage reports
# Usage: mise run test-coverage

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\test-coverage.ps1") @Args
