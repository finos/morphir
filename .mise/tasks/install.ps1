#MISE description="Install morphir CLI with go install"
#USAGE name install
#USAGE bin install
#USAGE about "Install morphir CLI with go install"
#USAGE usage "mise run install"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

Push-Location $repoRoot
go install ./cmd/morphir
Pop-Location
