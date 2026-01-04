# Installing Morphir

This guide covers different methods for installing the Morphir CLI on your system.

## Quick Install

### Using Installation Scripts

**Linux/macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/finos/morphir/main/scripts/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/finos/morphir/main/scripts/install.ps1 | iex
```

These scripts will:
- Download the latest release for your platform
- Verify checksums
- Install the binary to an appropriate location
- Add to your PATH (if needed)

### Using Go Install

If you have Go 1.25.5 or later installed:

```bash
go install github.com/finos/morphir/cmd/morphir@latest
```

This will install the latest version to `$GOPATH/bin` (usually `~/go/bin`).

**Install a specific version:**
```bash
go install github.com/finos/morphir/cmd/morphir@v0.3.0
```

## Manual Installation

### 1. Download Pre-built Binaries

Visit the [Releases page](https://github.com/finos/morphir/releases/latest) and download the appropriate binary for your platform:

- **Linux (x86_64)**: `morphir_VERSION_Linux_x86_64.tar.gz`
- **Linux (ARM64)**: `morphir_VERSION_Linux_arm64.tar.gz`
- **macOS (Intel)**: `morphir_VERSION_Darwin_x86_64.tar.gz`
- **macOS (Apple Silicon)**: `morphir_VERSION_Darwin_arm64.tar.gz`
- **Windows (x86_64)**: `morphir_VERSION_Windows_x86_64.tar.gz`

### 2. Extract the Archive

**Linux/macOS:**
```bash
tar -xzf morphir_VERSION_PLATFORM.tar.gz
```

**Windows:**
```powershell
tar -xzf morphir_VERSION_Windows_x86_64.tar.gz
```

### 3. Verify Checksum (Recommended)

Download `checksums.txt` from the same release and verify:

**Linux/macOS:**
```bash
sha256sum -c checksums.txt --ignore-missing
```

**Windows (PowerShell):**
```powershell
$expected = (Get-Content checksums.txt | Select-String "morphir_.*Windows").ToString().Split()[0]
$actual = (Get-FileHash morphir_VERSION_Windows_x86_64.tar.gz -Algorithm SHA256).Hash.ToLower()
if ($expected -eq $actual) { Write-Host "✓ Checksum verified" } else { Write-Host "✗ Checksum mismatch" }
```

### 4. Install the Binary

**Linux:**
```bash
sudo mv morphir /usr/local/bin/
sudo chmod +x /usr/local/bin/morphir
```

**macOS:**
```bash
sudo mv morphir /usr/local/bin/
sudo chmod +x /usr/local/bin/morphir
```

**Windows:**
1. Create a directory for Morphir (e.g., `C:\Program Files\Morphir`)
2. Move `morphir.exe` to that directory
3. Add the directory to your PATH:
   - Open "Edit the system environment variables"
   - Click "Environment Variables"
   - Under "System variables", find "Path" and click "Edit"
   - Click "New" and add `C:\Program Files\Morphir`
   - Click "OK" to save

## Verify Installation

After installation, verify Morphir is available:

```bash
morphir --version
```

You should see output like:
```
morphir version v0.3.0
```

## Platform-Specific Notes

### Linux

- Recommended install location: `/usr/local/bin/morphir`
- Ensure `/usr/local/bin` is in your PATH
- May require `sudo` for system-wide installation

### macOS

- Recommended install location: `/usr/local/bin/morphir`
- On first run, you may need to allow the app in System Preferences → Security & Privacy
- For Apple Silicon Macs, download the `Darwin_arm64` version
- For Intel Macs, download the `Darwin_x86_64` version

### Windows

- Recommended install location: `C:\Program Files\Morphir\morphir.exe`
- PowerShell may require execution policy changes:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```
- Windows Defender may flag the binary on first run - this is normal for new executables

## Building from Source

If you want to build from source instead:

```bash
# Clone the repository
git clone https://github.com/finos/morphir.git
cd morphir

# Set up development environment
./scripts/dev-setup.sh

# Build the CLI
just build

# The binary will be at ./bin/morphir
# Copy it to your PATH
sudo cp bin/morphir /usr/local/bin/
```

See [DEVELOPING.md](./DEVELOPING.md) for detailed development setup instructions.

## Troubleshooting

### Command not found

If you get "command not found" after installation:

1. **Verify the binary location:**
   ```bash
   which morphir  # Linux/macOS
   where morphir  # Windows
   ```

2. **Check your PATH:**
   ```bash
   echo $PATH  # Linux/macOS
   $env:PATH   # Windows PowerShell
   ```

3. **Add to PATH if needed:**
   ```bash
   # Linux/macOS (add to ~/.bashrc or ~/.zshrc)
   export PATH="$PATH:/usr/local/bin"

   # Windows PowerShell (run as Administrator)
   $env:PATH += ";C:\Program Files\Morphir"
   ```

### Permission denied

**Linux/macOS:**
```bash
chmod +x /usr/local/bin/morphir
```

**Windows:**
Right-click `morphir.exe` → Properties → Unblock

### go install fails

If `go install` fails with replace directive errors, ensure you're using version v0.3.0 or later:

```bash
go install github.com/finos/morphir/cmd/morphir@latest
```

Versions prior to v0.3.0 had replace directives that prevented `go install` from working.

### Architecture mismatch

Ensure you downloaded the correct binary for your system:

```bash
# Check your system architecture
uname -m  # Linux/macOS
$env:PROCESSOR_ARCHITECTURE  # Windows PowerShell
```

- `x86_64` or `AMD64` → Download x86_64 version
- `aarch64` or `ARM64` → Download arm64 version

## Updating Morphir

### Using Go Install

```bash
go install github.com/finos/morphir/cmd/morphir@latest
```

### Using Installation Scripts

Re-run the installation script (it will replace the existing version):

**Linux/macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/finos/morphir/main/scripts/install.sh | bash
```

**Windows:**
```powershell
irm https://raw.githubusercontent.com/finos/morphir/main/scripts/install.ps1 | iex
```

### Manual Update

1. Download the latest release
2. Replace the existing binary
3. Verify the new version:
   ```bash
   morphir --version
   ```

## Uninstalling Morphir

### If installed with go install

```bash
rm $(which morphir)
```

### If installed manually

**Linux/macOS:**
```bash
sudo rm /usr/local/bin/morphir
```

**Windows:**
1. Delete `C:\Program Files\Morphir\morphir.exe`
2. Remove from PATH (reverse the PATH addition steps)

## Getting Help

- **Documentation**: https://morphir.finos.org
- **Issues**: https://github.com/finos/morphir/issues
- **Discussions**: https://github.com/finos/morphir/discussions
- **Command help**: `morphir --help`

## Next Steps

After installation, try these commands to get started:

```bash
# Show help
morphir --help

# Show version
morphir --version

# Initialize a new Morphir workspace (example)
morphir workspace init

# See all available commands
morphir --help
```

For development and contribution, see [DEVELOPING.md](./DEVELOPING.md).
