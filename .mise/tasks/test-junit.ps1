#MISE description="Run tests with JUnit XML output"
#USAGE name test-junit
#USAGE bin test-junit
#USAGE about "Run tests with JUnit XML output"
#USAGE usage "mise run test-junit"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\test-junit.ps1") @Args
