#MISE description="Link Codex skills to Claude skills"
#USAGE name link-skills.ps1
#USAGE bin link-skills.ps1
#USAGE about "Link Codex skills to Claude skills"
#USAGE usage "mise run link-skills"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\link-skills.ps1") @Args
