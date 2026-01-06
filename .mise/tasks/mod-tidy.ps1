 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\mod-tidy.ps1") @Args
