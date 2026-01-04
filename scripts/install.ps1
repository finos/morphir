# Morphir Installation Script for Windows
# Downloads and installs the latest Morphir release

$ErrorActionPreference = "Stop"

Write-Host "Morphir Installation Script" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

# Detect architecture
$Arch = $env:PROCESSOR_ARCHITECTURE
switch ($Arch) {
    "AMD64" { $ArchType = "x86_64" }
    "ARM64" { $ArchType = "arm64" }
    default {
        Write-Host "✗ Unsupported architecture: $Arch" -ForegroundColor Red
        Write-Host "Supported architectures: AMD64 (x86_64), ARM64"
        exit 1
    }
}

Write-Host "Detected: Windows $ArchType"
Write-Host ""

# Get latest release version from GitHub
Write-Host "Fetching latest release..."
try {
    $ApiResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/finos/morphir/releases/latest"
    $LatestVersion = $ApiResponse.tag_name
    Write-Host "✓ Latest version: $LatestVersion" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to fetch latest release version" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

Write-Host ""

# Construct download URL
$VersionNumber = $LatestVersion -replace '^v', ''
$Filename = "morphir_${VersionNumber}_Windows_${ArchType}.tar.gz"
$DownloadUrl = "https://github.com/finos/morphir/releases/download/${LatestVersion}/${Filename}"
$ChecksumsUrl = "https://github.com/finos/morphir/releases/download/${LatestVersion}/checksums.txt"

# Create temporary directory
$TempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "morphir-install-$(Get-Random)")
try {
    Push-Location $TempDir.FullName

    # Download binary archive
    Write-Host "Downloading $Filename..."
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $Filename -UseBasicParsing
        Write-Host "✓ Download complete" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Download failed" -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }

    # Download checksums
    Write-Host ""
    Write-Host "Downloading checksums..."
    try {
        Invoke-WebRequest -Uri $ChecksumsUrl -OutFile "checksums.txt" -UseBasicParsing
        Write-Host "✓ Checksums downloaded" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠ Warning: Could not download checksums (continuing anyway)" -ForegroundColor Yellow
    }

    # Verify checksum if available
    if (Test-Path "checksums.txt") {
        Write-Host ""
        Write-Host "Verifying checksum..."
        $ExpectedHash = (Get-Content checksums.txt | Select-String $Filename).ToString().Split()[0]
        $ActualHash = (Get-FileHash $Filename -Algorithm SHA256).Hash.ToLower()

        if ($ExpectedHash -eq $ActualHash) {
            Write-Host "✓ Checksum verified" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ Warning: Checksum verification failed (continuing anyway)" -ForegroundColor Yellow
            Write-Host "Expected: $ExpectedHash"
            Write-Host "Actual:   $ActualHash"
        }
    }

    # Extract archive
    Write-Host ""
    Write-Host "Extracting archive..."
    tar -xzf $Filename
    Write-Host "✓ Extraction complete" -ForegroundColor Green

    # Determine install location
    $InstallDir = "$env:ProgramFiles\Morphir"

    # Check if we need admin privileges
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $IsAdmin) {
        Write-Host ""
        Write-Host "⚠ Warning: Running without administrator privileges" -ForegroundColor Yellow
        Write-Host "Installing to user directory instead..."
        $InstallDir = "$env:LOCALAPPDATA\Programs\Morphir"
    }

    # Create install directory if it doesn't exist
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Install binary
    Write-Host ""
    Write-Host "Installing to $InstallDir..."
    Copy-Item -Path "morphir.exe" -Destination "$InstallDir\morphir.exe" -Force
    Write-Host "✓ Installation complete" -ForegroundColor Green

    # Check if in PATH
    $PathParts = $env:PATH -split ';'
    $InPath = $PathParts -contains $InstallDir

    if (-not $InPath) {
        Write-Host ""
        Write-Host "Adding to PATH..."

        if ($IsAdmin) {
            # Add to system PATH
            $CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($CurrentPath -notlike "*$InstallDir*") {
                [Environment]::SetEnvironmentVariable("PATH", "$CurrentPath;$InstallDir", "Machine")
                $env:PATH = "$env:PATH;$InstallDir"
                Write-Host "✓ Added to system PATH" -ForegroundColor Green
            }
        }
        else {
            # Add to user PATH
            $CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if ($CurrentPath -notlike "*$InstallDir*") {
                [Environment]::SetEnvironmentVariable("PATH", "$CurrentPath;$InstallDir", "User")
                $env:PATH = "$env:PATH;$InstallDir"
                Write-Host "✓ Added to user PATH" -ForegroundColor Green
            }
        }

        Write-Host ""
        Write-Host "⚠ You may need to restart your terminal for PATH changes to take effect" -ForegroundColor Yellow
    }

    # Verify installation
    Write-Host ""
    $MorphirPath = Get-Command morphir -ErrorAction SilentlyContinue
    if ($MorphirPath) {
        $Version = & morphir --version 2>&1
        Write-Host "✓ Morphir successfully installed!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Version: $Version"
        Write-Host "Location: $($MorphirPath.Source)"
    }
    else {
        Write-Host "⚠ Morphir installed but not found in PATH" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Please restart your terminal or run:"
        Write-Host "  `$env:PATH += `";$InstallDir`""
    }

    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  morphir --help          # Show help"
    Write-Host "  morphir --version       # Show version"
    Write-Host ""
    Write-Host "For documentation, visit: https://morphir.finos.org"
    Write-Host ""
}
finally {
    # Cleanup
    Pop-Location
    Remove-Item -Path $TempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
