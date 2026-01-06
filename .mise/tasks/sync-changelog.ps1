#MISE description="Sync CHANGELOG.md into cmd/morphir"
#MISE usage="mise run sync-changelog"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\sync-changelog.ps1") @Args
