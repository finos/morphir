#MISE description="Build the morphir-dev CLI"
#USAGE name build-dev
#USAGE bin build-dev
#USAGE about "Build the morphir-dev CLI"
#USAGE usage "mise run build-dev"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\build-dev.ps1") @Args
