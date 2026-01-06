#MISE description="Set up local Go workspace"
#USAGE name dev-setup
#USAGE bin dev-setup
#USAGE about "Set up local Go workspace"
#USAGE usage "mise run dev-setup"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\dev-setup.ps1") @Args
