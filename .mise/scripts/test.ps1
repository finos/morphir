# PowerShell wrapper script to run tests on Windows
# Calls the TypeScript task via bun since mise file tasks don't work on Windows

$scriptPath = Join-Path $PSScriptRoot "..\tasks\test.ts"
bun $scriptPath @args

exit $LASTEXITCODE
