# PowerShell wrapper script to set up Go workspace on Windows
# Calls the TypeScript task via bun since mise file tasks don't work on Windows

$scriptPath = Join-Path $PSScriptRoot "..\tasks\workspace\setup.ts"
bun $scriptPath @args

exit $LASTEXITCODE
