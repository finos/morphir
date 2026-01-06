#MISE description="Build a release snapshot"
#USAGE name release-snapshot
#USAGE bin release-snapshot
#USAGE about "Build a release snapshot"
#USAGE usage "mise run release-snapshot"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\release-snapshot.ps1") @Args
