#MISE description="Sync CHANGELOG.md into cmd/morphir"
#USAGE name sync-changelog
#USAGE bin sync-changelog
#USAGE about "Sync CHANGELOG.md into cmd/morphir"
#USAGE usage "mise run sync-changelog"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\sync-changelog.ps1") @Args
