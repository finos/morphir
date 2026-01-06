#MISE description="Install morphir-dev to Go bin"
#USAGE name install-dev
#USAGE bin install-dev
#USAGE about "Install morphir-dev to Go bin"
#USAGE usage "mise run install-dev"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\install-dev.ps1") @Args
