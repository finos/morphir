#MISE description="Build the morphir CLI"
#USAGE name build
#USAGE bin build
#USAGE about "Build the morphir CLI"
#USAGE usage "mise run build"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\build.ps1") @Args
