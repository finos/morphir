 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\build.ps1") @Args
