$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& bash (Join-Path $scriptDir "release.sh") @Args
