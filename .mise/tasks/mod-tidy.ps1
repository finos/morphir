#MISE description="Run go mod tidy for all modules"
#USAGE name mod-tidy
#USAGE bin mod-tidy
#USAGE about "Run go mod tidy for all modules"
#USAGE usage "mise run mod-tidy"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\mod-tidy.ps1") @Args
