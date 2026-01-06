#MISE description="Run a release dry-run"
#USAGE name release-test
#USAGE bin release-test
#USAGE about "Run a release dry-run"
#USAGE usage "mise run release-test"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\release-test.ps1") @Args
