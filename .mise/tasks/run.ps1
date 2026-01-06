#MISE description="Run morphir CLI"
#USAGE name run
#USAGE bin run
#USAGE about "Run morphir CLI"
#USAGE usage "mise run run"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\run.ps1") @Args
