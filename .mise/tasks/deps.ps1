#MISE description="Download Go module dependencies"
#USAGE name deps
#USAGE bin deps
#USAGE about "Download Go module dependencies"
#USAGE usage "mise run deps"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\deps.ps1") @Args
