#MISE description="Validate GoReleaser configuration"
#USAGE name goreleaser-check
#USAGE bin goreleaser-check
#USAGE about "Validate GoReleaser configuration"
#USAGE usage "mise run goreleaser-check"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\goreleaser-check.ps1") @Args
