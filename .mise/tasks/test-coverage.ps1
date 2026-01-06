#MISE description="Run tests with coverage reports"
#USAGE name test-coverage
#USAGE bin test-coverage
#USAGE about "Run tests with coverage reports"
#USAGE usage "mise run test-coverage"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\test-coverage.ps1") @Args
