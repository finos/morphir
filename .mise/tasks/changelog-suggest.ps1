# Description: Suggest changelog entries
# Usage: mise run changelog-suggest

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\changelog-suggest.ps1") @Args
