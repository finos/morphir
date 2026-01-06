$ErrorActionPreference = "Stop"

Copy-Item -Path "CHANGELOG.md" -Destination "cmd/morphir/cmd/CHANGELOG.md" -Force
