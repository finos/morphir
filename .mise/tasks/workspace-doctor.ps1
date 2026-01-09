#MISE description="Diagnose Go workspace issues and offer local fixes"
#USAGE name workspace-doctor
#USAGE bin workspace-doctor
#USAGE about "Diagnose Go workspace issues and offer local fixes"
#USAGE usage "mise run workspace-doctor -- --fix replace|tags|none"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

& (Join-Path $RepoRoot "scripts/workspace-doctor.ps1") @args
