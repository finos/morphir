# PowerShell wrapper script to build morphir CLI on Windows
# Calls the TypeScript task via bun since mise file tasks don't work on Windows

$scriptPath = Join-Path $PSScriptRoot "..\tasks\build.ts"
bun $scriptPath @args

exit $LASTEXITCODE
