#MISE description="Sync CHANGELOG.md into cmd/morphir"
#USAGE name sync-changelog.ps1
#USAGE bin sync-changelog.ps1
#USAGE about "Sync CHANGELOG.md into cmd/morphir"
#USAGE usage "mise run sync-changelog"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\sync-changelog.ps1") @Args
