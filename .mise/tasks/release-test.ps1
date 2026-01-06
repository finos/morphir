# Description: Run a release dry-run
# Usage: mise run release-test

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\release-test.ps1") @Args
