#MISE description="Run format, verify, test, and lint"
#USAGE name ci-check
#USAGE bin ci-check
#USAGE about "Run format, verify, test, and lint"
#USAGE usage "mise run ci-check"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\ci-check.ps1") @Args
