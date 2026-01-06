#MISE description="Suggest changelog entries"
#USAGE name changelog-suggest
#USAGE bin changelog-suggest
#USAGE about "Suggest changelog entries"
#USAGE usage "mise run changelog-suggest"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\changelog-suggest.ps1") @Args
