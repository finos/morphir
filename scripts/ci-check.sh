#!/usr/bin/env bash
set -euo pipefail

mise run fmt-check
mise run verify
mise run test
mise run lint

echo "✓ All CI checks passed!"
