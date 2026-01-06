#MISE description="Validate GoReleaser configuration"
#USAGE name goreleaser-check.ps1
#USAGE bin goreleaser-check.ps1
#USAGE about "Validate GoReleaser configuration"
#USAGE usage "mise run goreleaser-check"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\goreleaser-check.ps1") @Args
