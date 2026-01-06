$ErrorActionPreference = "Stop"

Write-Host "Validating GoReleaser configuration..."
if (Get-Command goreleaser -ErrorAction SilentlyContinue) {
    goreleaser check
} else {
    Write-Host "goreleaser not found. Install with: go install github.com/goreleaser/goreleaser@latest"
    exit 1
}
