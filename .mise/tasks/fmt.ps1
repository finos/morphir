#MISE description="Format Go code"
#USAGE name fmt
#USAGE bin fmt
#USAGE about "Format Go code"
#USAGE usage "mise run fmt"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\fmt.ps1") @Args
