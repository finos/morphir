$ErrorActionPreference = "Stop"

Write-Host "Testing release process..."
if (Get-Command goreleaser -ErrorAction SilentlyContinue) {
    goreleaser release --skip=publish --clean
} else {
    Write-Host "goreleaser not found. Install with: go install github.com/goreleaser/goreleaser@latest"
    exit 1
}
