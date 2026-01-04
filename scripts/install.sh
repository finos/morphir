#!/usr/bin/env bash
# Morphir Installation Script for Linux/macOS
# Downloads and installs the latest Morphir release

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Morphir Installation Script"
echo "============================="
echo ""

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Linux*)     OS_TYPE=Linux;;
    Darwin*)    OS_TYPE=Darwin;;
    *)
        echo -e "${RED}✗ Unsupported operating system: $OS${NC}"
        echo "This script supports Linux and macOS only."
        echo "For Windows, use install.ps1"
        exit 1
        ;;
esac

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)     ARCH_TYPE=x86_64;;
    aarch64)    ARCH_TYPE=arm64;;
    arm64)      ARCH_TYPE=arm64;;
    *)
        echo -e "${RED}✗ Unsupported architecture: $ARCH${NC}"
        echo "Supported architectures: x86_64, arm64"
        exit 1
        ;;
esac

echo "Detected: $OS_TYPE $ARCH_TYPE"
echo ""

# Get latest release version from GitHub
echo "Fetching latest release..."
LATEST_VERSION=$(curl -sL https://api.github.com/repos/finos/morphir/releases/latest | grep '"tag_name"' | cut -d'"' -f4)

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${RED}✗ Failed to fetch latest release version${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Latest version: $LATEST_VERSION${NC}"
echo ""

# Construct download URL
FILENAME="morphir_${LATEST_VERSION#v}_${OS_TYPE}_${ARCH_TYPE}.tar.gz"
DOWNLOAD_URL="https://github.com/finos/morphir/releases/download/${LATEST_VERSION}/${FILENAME}"
CHECKSUMS_URL="https://github.com/finos/morphir/releases/download/${LATEST_VERSION}/checksums.txt"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"

# Download binary archive
echo "Downloading $FILENAME..."
if curl -L -o "$FILENAME" "$DOWNLOAD_URL"; then
    echo -e "${GREEN}✓ Download complete${NC}"
else
    echo -e "${RED}✗ Download failed${NC}"
    exit 1
fi

# Download checksums
echo ""
echo "Downloading checksums..."
if curl -L -o checksums.txt "$CHECKSUMS_URL"; then
    echo -e "${GREEN}✓ Checksums downloaded${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Could not download checksums (continuing anyway)${NC}"
fi

# Verify checksum if available
if [ -f checksums.txt ]; then
    echo ""
    echo "Verifying checksum..."
    if sha256sum -c checksums.txt --ignore-missing 2>/dev/null; then
        echo -e "${GREEN}✓ Checksum verified${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Checksum verification failed (continuing anyway)${NC}"
    fi
fi

# Extract archive
echo ""
echo "Extracting archive..."
tar -xzf "$FILENAME"
echo -e "${GREEN}✓ Extraction complete${NC}"

# Determine install location
if [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
    NEEDS_SUDO=false
else
    INSTALL_DIR="/usr/local/bin"
    NEEDS_SUDO=true
fi

# Install binary
echo ""
echo "Installing to $INSTALL_DIR..."
if [ "$NEEDS_SUDO" = true ]; then
    echo "This requires sudo privileges."
    sudo mv morphir "$INSTALL_DIR/morphir"
    sudo chmod +x "$INSTALL_DIR/morphir"
else
    mv morphir "$INSTALL_DIR/morphir"
    chmod +x "$INSTALL_DIR/morphir"
fi
echo -e "${GREEN}✓ Installation complete${NC}"

# Verify installation
echo ""
if command -v morphir &> /dev/null; then
    VERSION=$(morphir --version 2>&1 || echo "unknown")
    echo -e "${GREEN}✓ Morphir successfully installed!${NC}"
    echo ""
    echo "Version: $VERSION"
    echo "Location: $(which morphir)"
else
    echo -e "${YELLOW}⚠ Morphir installed but not in PATH${NC}"
    echo ""
    echo "Add $INSTALL_DIR to your PATH:"
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    echo ""
    echo "Add this to your ~/.bashrc or ~/.zshrc to make it permanent."
fi

echo ""
echo "Next steps:"
echo "  morphir --help          # Show help"
echo "  morphir --version       # Show version"
echo ""
echo "For documentation, visit: https://morphir.finos.org"
echo ""
