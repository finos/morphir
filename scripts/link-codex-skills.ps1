$ErrorActionPreference = "Stop"

$claudeDir = $env:CLAUDE_DIR
if ([string]::IsNullOrEmpty($claudeDir)) {
    $claudeDir = Join-Path $HOME ".claude"
}

$codexDir = $env:CODEX_DIR
if ([string]::IsNullOrEmpty($codexDir)) {
    $codexDir = Join-Path $HOME ".codex"
}

$claudeSkills = Join-Path $claudeDir "skills"
$codexSkills = Join-Path $codexDir "skills"

try {
    New-Item -ItemType Directory -Force -Path $claudeSkills | Out-Null
} catch {
    Write-Warning "Unable to create $claudeSkills; skipping Codex skills link. $($_.Exception.Message)"
    exit 0
}

$item = Get-Item -Path $codexSkills -Force -ErrorAction SilentlyContinue
if ($item) {
    $isSymlink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isSymlink) {
        if ($item.Target -eq $claudeSkills) {
            exit 0
        }
        Write-Warning "$codexSkills points to $($item.Target) (expected $claudeSkills)."
        exit 0
    }
    Write-Warning "$codexSkills exists and is not a symlink; leaving as-is."
    exit 0
}

try {
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
    New-Item -ItemType SymbolicLink -Path $codexSkills -Target $claudeSkills | Out-Null
    Write-Host "Linked $codexSkills -> $claudeSkills" -ForegroundColor DarkGray
} catch {
    Write-Warning "Failed to create symlink $codexSkills -> $claudeSkills. $($_.Exception.Message)"
}
