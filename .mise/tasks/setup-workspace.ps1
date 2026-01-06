#MISE description="Generate go.work for all modules"
#USAGE name setup-workspace
#USAGE bin setup-workspace
#USAGE about "Generate go.work for all modules"
#USAGE usage "mise run setup-workspace"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\setup-workspace.ps1") @Args
