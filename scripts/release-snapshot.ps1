$ErrorActionPreference = "Stop"

Write-Host "Building release snapshot..."
if (Get-Command goreleaser -ErrorAction SilentlyContinue) {
    goreleaser release --snapshot --clean --skip=publish
} else {
    Write-Host "goreleaser not found. Install with: go install github.com/goreleaser/goreleaser@latest"
    exit 1
}
