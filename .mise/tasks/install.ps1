# Description: Install morphir CLI with go install
# Usage: mise run install

 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = Split-Path -Parent (Split-Path -Parent )

Set-Location 
go install ./cmd/morphir
