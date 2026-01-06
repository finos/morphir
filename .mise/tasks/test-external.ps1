#MISE description="Test external consumption without go.work"
#USAGE name test-external
#USAGE bin test-external
#USAGE about "Test external consumption without go.work"
#USAGE usage "mise run test-external"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\test-external.ps1") @Args
