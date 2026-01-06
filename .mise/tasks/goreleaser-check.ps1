#MISE description="Validate GoReleaser configuration"
#MISE usage="mise run goreleaser-check"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\goreleaser-check.ps1") @Args
