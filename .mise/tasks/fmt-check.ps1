#MISE description="Check Go formatting"
#USAGE name fmt-check
#USAGE bin fmt-check
#USAGE about "Check Go formatting"
#USAGE usage "mise run fmt-check"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\fmt-check.ps1") @Args
