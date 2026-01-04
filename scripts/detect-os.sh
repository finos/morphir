#!/usr/bin/env bash
# Detect the operating system and output a normalized value

if [ -n "$OS" ] && [[ "$OS" == *"Windows"* ]]; then
    echo "windows"
elif [ -n "$OSTYPE" ]; then
    case "$OSTYPE" in
        linux-gnu*)    echo "linux" ;;
        darwin*)       echo "darwin" ;;
        msys|cygwin)   echo "windows" ;;
        *)             echo "unknown" ;;
    esac
elif command -v uname > /dev/null 2>&1; then
    case "$(uname -s)" in
        Linux*)    echo "linux" ;;
        Darwin*)   echo "darwin" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)         echo "unknown" ;;
    esac
else
    echo "unknown"
fi
