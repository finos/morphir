#MISE description="Run golangci-lint"
#USAGE name lint
#USAGE bin lint
#USAGE about "Run golangci-lint"
#USAGE usage "mise run lint"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\lint.ps1") @Args
