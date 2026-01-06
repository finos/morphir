#MISE description="Prepare release tags"
#USAGE name release-prepare
#USAGE bin release-prepare
#USAGE about "Prepare release tags"
#USAGE usage "mise run release-prepare -- vX.Y.Z"
#USAGE arg <version> help="Semver tag like v1.2.3"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\release-prepare.ps1") @Args
