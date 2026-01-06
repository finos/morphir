#MISE description="Run morphir-dev CLI"
#USAGE name run-dev
#USAGE bin run-dev
#USAGE about "Run morphir-dev CLI"
#USAGE usage "mise run run-dev"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\run-dev.ps1") @Args
