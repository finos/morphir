$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "sync-changelog.ps1")

Write-Host "Checking code formatting..."
$unformatted = gofmt -s -l .
if ($unformatted) {
    Write-Host "The following files are not formatted:"
    $unformatted | ForEach-Object { Write-Host $_ }
    Write-Host ""
    Write-Host "Run 'mise run fmt' to fix formatting issues."
    exit 1
} else {
    Write-Host "✓ All files are properly formatted"
}
