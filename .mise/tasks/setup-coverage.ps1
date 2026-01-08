#MISE description="Set up and verify code coverage for all modules"
#USAGE name setup-coverage
#USAGE bin setup-coverage
#USAGE about "Set up and verify code coverage for all modules"
#USAGE usage "mise run setup-coverage [-Check|-List]"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\setup-coverage.ps1") @Args
