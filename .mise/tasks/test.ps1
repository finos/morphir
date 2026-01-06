#MISE description="Run all Go tests"
#USAGE name test
#USAGE bin test
#USAGE about "Run all Go tests"
#USAGE usage "mise run test"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\test.ps1") @Args
