#MISE description="Run a release dry-run"
#USAGE name release-test.ps1
#USAGE bin release-test.ps1
#USAGE about "Run a release dry-run"
#USAGE usage "mise run release-test"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\release-test.ps1") @Args
