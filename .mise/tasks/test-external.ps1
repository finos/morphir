# Description: Test external consumption without go.work
# Usage: mise run test-external

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\test-external.ps1") @Args
