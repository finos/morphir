 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\run.ps1") @Args
