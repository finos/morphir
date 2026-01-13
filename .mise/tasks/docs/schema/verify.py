#!/usr/bin/env python3
# #MISE description="Verify YAML and JSON schema files are in sync"
"""
Wrapper for schema verification.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def find_repo_root() -> Path:
    """Find the repository root by looking for .git"""
    current: Path = Path.cwd()
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    return Path.cwd()


def main() -> int:
    root: Path = find_repo_root()
    script: Path = root / ".claude" / "skills" / "technical-writer" / "scripts" / "convert_schema.py"

    if not script.exists():
        print(f"Error: Script not found: {script}", file=sys.stderr)
        return 1

    result: subprocess.CompletedProcess[bytes] = subprocess.run(
        [sys.executable, str(script), "--verify", "website/static/schemas/"],
        cwd=root
    )
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
