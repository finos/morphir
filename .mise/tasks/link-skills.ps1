# Description: Link Codex skills to Claude skills
# Usage: mise run link-skills

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

& (Join-Path  "scripts\link-skills.ps1") @Args
