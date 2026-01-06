#MISE description="Format Go code"
#USAGE name fmt.ps1
#USAGE bin fmt.ps1
#USAGE about "Format Go code"
#USAGE usage "mise run fmt"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\fmt.ps1") @Args
