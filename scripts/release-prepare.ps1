$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& bash (Join-Path $scriptDir "release-prep.sh") @Args
