# Description: Build a release snapshot
# Usage: mise run release-snapshot

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\release-snapshot.ps1") @Args
