#MISE description="Install morphir CLI with go install"
#USAGE name install.ps1
#USAGE bin install.ps1
#USAGE about "Install morphir CLI with go install"
#USAGE usage "mise run install"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

Set-Location 
go install ./cmd/morphir
