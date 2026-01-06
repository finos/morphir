#MISE description="Format Go code"
#MISE usage="mise run fmt"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\fmt.ps1") @Args
