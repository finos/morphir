#MISE description="Run full dev environment setup"
#USAGE name setup
#USAGE bin setup
#USAGE about "Run full dev environment setup"
#USAGE usage "mise run setup"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\setup.ps1") @Args
