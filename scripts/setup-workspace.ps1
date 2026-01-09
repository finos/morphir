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

# Remove existing go.work if present (idempotent operation)
Remove-Item -Path "go.work", "go.work.sum" -ErrorAction SilentlyContinue

# Initialize go.work
go work init

# Add all discovered modules
foreach ($Module in $Modules) {
    Write-Host "  ✓ Adding: $Module" -ForegroundColor Green
    go work use "./$Module"
}

Write-Host ""
Write-Host "🔁 Syncing workspace..." -ForegroundColor Blue
try {
    go work sync | Out-Null
    Write-Host "  ✓ Workspace synced successfully" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Workspace sync failed (local dev still works without sync)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🔧 Workspace location:" -ForegroundColor Blue
Write-Host ("  " + (go env GOWORK)) -ForegroundColor Gray

Write-Host ""
Write-Host "🔎 Sanity checks..." -ForegroundColor Blue
$ReplaceHits = & rg -n "^replace " --glob "*/go.mod" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ⚠ Found replace directives in go.mod files (remove them and use go.work)" -ForegroundColor Yellow
} else {
    Write-Host "  ✓ No replace directives in go.mod files" -ForegroundColor Green
}

$WorkspaceStaged = git status --short | Select-String "go.work"
if ($WorkspaceStaged) {
    Write-Host "  ⚠ go.work or go.work.sum is staged (do not commit workspace files)" -ForegroundColor Yellow
} else {
    Write-Host "  ✓ go.work files are not staged" -ForegroundColor Green
}

Write-Host ""
Write-Host "🏷️  Checking internal module tags..." -ForegroundColor Blue
$MissingTags = 0
$MissingReplaces = 0
$ReplaceSpecs = @()
$ModFiles = Get-ChildItem -Path . -Filter "go.mod" -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\vendor\\' -and $_.FullName -notmatch '\\node_modules\\' } |
    Sort-Object FullName

foreach ($ModFile in $ModFiles) {
    Get-Content $ModFile.FullName | ForEach-Object {
        if ($_ -match 'github.com/finos/morphir/') {
            $parts = ($_ -split '\s+') | Where-Object { $_ -ne "" }
            if ($parts.Length -ge 2) {
                $module = $parts[0]
                $version = $parts[1]
                if ($module -like "github.com/finos/morphir/*" -and $version -match '^v') {
                    $path = $module.Replace("github.com/finos/morphir/", "")
                    $tag = "$path/$version"
                    $tagMatch = git tag -l $tag
                    if (-not $tagMatch) {
                        Write-Host "  ⚠ Missing tag for $module ($version) -> expected tag $tag" -ForegroundColor Yellow
                        $MissingTags++
                        $localPath = Join-Path $ProjectRoot $path
                        if (Test-Path $localPath) {
                            $ReplaceSpecs += "$module@$version=./$path"
                        }
                    }
                }
            }
        }
    }
}

if ($MissingTags -eq 0) {
    Write-Host "  ✓ All internal module version tags found" -ForegroundColor Green
} else {
    Write-Host "  ⚠ $MissingTags internal module tag(s) missing (workspace will not override invalid versions)" -ForegroundColor Yellow
    if ($ReplaceSpecs.Count -gt 0) {
        Write-Host "  🔧 Adding go.work replace directives for missing tags..." -ForegroundColor Cyan
        foreach ($spec in $ReplaceSpecs) {
            go work edit -replace=$spec
            Write-Host "    ✓ replace $spec" -ForegroundColor Green
            $MissingReplaces++
        }
        Write-Host "  ✅ Added $MissingReplaces local-only replace directive(s) to go.work" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "✅ Workspace configured successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Modules in workspace:" -ForegroundColor Cyan
go work use | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
