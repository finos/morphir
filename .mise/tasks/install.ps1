#MISE description="Install morphir CLI with go install"
#MISE usage="mise run install"

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

Set-Location 
go install ./cmd/morphir
