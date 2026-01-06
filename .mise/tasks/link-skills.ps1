#MISE description="Link Codex skills to Claude skills"
#USAGE name link-skills
#USAGE bin link-skills
#USAGE about "Link Codex skills to Claude skills"
#USAGE usage "mise run link-skills"

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

& (Join-Path $repoRoot "scripts\link-skills.ps1") @Args
