#MISE description="Run release automation"
#USAGE name release
#USAGE bin release
#USAGE about "Run release automation"
#USAGE usage "mise run release -- vX.Y.Z"
#USAGE arg <version> help="Semver tag like v1.2.3"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\release.ps1") @Args
