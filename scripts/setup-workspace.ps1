# Dynamically set up go.work for local module development
# This script discovers all Go modules in the repository and adds them to go.work

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Set-Location $ProjectRoot

Write-Host "🔍 Discovering Go modules..." -ForegroundColor Blue

# Find all go.mod files (excluding vendor and node_modules)
$ModFiles = Get-ChildItem -Path . -Filter "go.mod" -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\vendor\\' -and $_.FullName -notmatch '\\node_modules\\' } |
    Sort-Object FullName

if ($ModFiles.Count -eq 0) {
    Write-Host "❌ No Go modules found!" -ForegroundColor Red
    exit 1
}

$Modules = @()
foreach ($ModFile in $ModFiles) {
    $ModDir = Split-Path -Parent $ModFile.FullName
    $RelDir = (Resolve-Path -Relative $ModDir).TrimStart(".\")
    $Modules += $RelDir
    Write-Host "  ✓ Found module: $RelDir" -ForegroundColor Green
}

Write-Host ""
Write-Host "📦 Setting up go.work with $($Modules.Count) modules..." -ForegroundColor Blue

# Initialize go.work
go work init

# Add all discovered modules
foreach ($Module in $Modules) {
    Write-Host "  ✓ Adding: $Module" -ForegroundColor Green
    go work use "./$Module"
}

Write-Host ""
Write-Host "✅ Workspace configured successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Modules in workspace:" -ForegroundColor Cyan
go work use | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
