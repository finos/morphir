#MISE description="Clean build artifacts"
#USAGE name clean
#USAGE bin clean
#USAGE about "Clean build artifacts"
#USAGE usage "mise run clean"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\clean.ps1") @Args
