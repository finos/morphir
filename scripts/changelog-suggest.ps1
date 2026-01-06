$ErrorActionPreference = "Stop"

Write-Host "Morphir Changelog Suggestion Tool"
Write-Host "=================================="
Write-Host ""

$lastTag = ""
try {
    $lastTag = git describe --tags --abbrev=0 2>$null
} catch {
    $lastTag = ""
}

if ([string]::IsNullOrEmpty($lastTag)) {
    Write-Host "No previous tags found. Showing all commits."
    $commitRange = "HEAD"
} else {
    Write-Host "Last release: $lastTag"
    $commitRange = "$lastTag..HEAD"
}

Write-Host ""
Write-Host "Analyzing commits since last release..."
Write-Host ""

$commits = git log $commitRange --oneline --no-merges
if ([string]::IsNullOrEmpty($commits)) {
    Write-Host "No new commits since last release."
    exit 0
}

$commitLines = $commits -split "`n" | Where-Object { $_ -ne "" }
Write-Host "Total commits: $($commitLines.Count)"
Write-Host ""

Write-Host "=== Suggested Changelog Entries ==="
Write-Host ""

$features = git log $commitRange --oneline --no-merges --grep="^feat" 2>$null
if ($features) {
    Write-Host "### Added"
    $features -split "`n" | ForEach-Object { $_ -replace '^[a-f0-9]* feat[:(]', '- ' -replace '\):', ':' } | Write-Host
    Write-Host ""
}

$fixes = git log $commitRange --oneline --no-merges --grep="^fix" 2>$null
if ($fixes) {
    Write-Host "### Fixed"
    $fixes -split "`n" | ForEach-Object { $_ -replace '^[a-f0-9]* fix[:(]', '- ' -replace '\):', ':' } | Write-Host
    Write-Host ""
}

$changes = git log $commitRange --oneline --no-merges --grep="^refactor|^perf|^chore.*update" 2>$null
if ($changes) {
    Write-Host "### Changed"
    $changes -split "`n" | ForEach-Object { $_ -replace '^[a-f0-9]* [^:]*[:(]', '- ' -replace '\):', ':' } | Write-Host
    Write-Host ""
}

$docs = git log $commitRange --oneline --no-merges --grep="^docs" 2>$null
if ($docs) {
    Write-Host "### Documentation"
    $docs -split "`n" | ForEach-Object { $_ -replace '^[a-f0-9]* docs[:(]', '- ' -replace '\):', ':' } | Write-Host
    Write-Host ""
}

$breaking = git log $commitRange --oneline --no-merges --grep="BREAKING CHANGE|!" 2>$null
if ($breaking) {
    Write-Host "WARNING: BREAKING CHANGES DETECTED"
    $breaking -split "`n" | ForEach-Object { $_ -replace '^[a-f0-9]* ', '- ' } | Write-Host
    Write-Host ""
    Write-Host "This suggests a MAJOR version bump!"
    Write-Host ""
}

Write-Host "=== Other Commits (review manually) ==="
Write-Host ""
$otherCommits = git log $commitRange --oneline --no-merges --invert-grep --grep="^feat|^fix|^docs|^style|^refactor|^perf|^test|^chore" 2>$null
if ($otherCommits) {
    $otherCommits | Write-Host
} else {
    Write-Host "None"
}
Write-Host ""

Write-Host "=== Version Bump Suggestion ==="
Write-Host ""

if ($breaking) {
    Write-Host "Suggested: MAJOR version bump (breaking changes)"
} elseif ($features) {
    Write-Host "Suggested: MINOR version bump (new features)"
} elseif ($fixes) {
    Write-Host "Suggested: PATCH version bump (bug fixes only)"
} else {
    Write-Host "Suggested: PATCH version bump (changes detected)"
}

Write-Host ""
Write-Host "To update CHANGELOG.md:"
Write-Host "  1. Edit CHANGELOG.md"
Write-Host "  2. Move items from [Unreleased] to [X.Y.Z] - $(Get-Date -Format 'yyyy-MM-dd')"
Write-Host "  3. Add entries suggested above"
Write-Host "  4. Commit: git commit -m 'chore: prepare release vX.Y.Z'"
Write-Host ""
