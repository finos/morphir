#MISE description="Suggest changelog entries"
#USAGE name changelog-suggest.ps1
#USAGE bin changelog-suggest.ps1
#USAGE about "Suggest changelog entries"
#USAGE usage "mise run changelog-suggest"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\changelog-suggest.ps1") @Args
