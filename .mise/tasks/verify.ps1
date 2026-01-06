#MISE description="Verify all modules build"
#USAGE name verify
#USAGE bin verify
#USAGE about "Verify all modules build"
#USAGE usage "mise run verify"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\verify.ps1") @Args
