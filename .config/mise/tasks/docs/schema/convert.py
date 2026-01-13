#!/usr/bin/env python3
# #MISE description="Convert YAML JSON Schema files to JSON format"
# #USAGE flag "--verify" help="Verify YAML and JSON schema files are in sync"
# #USAGE arg "[path]" help="Path to schemas directory" default="website/static/schemas/"
"""
Wrapper for schema conversion script.
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

    args: list[str] = sys.argv[1:] if len(sys.argv) > 1 else ["website/static/schemas/"]

    result: subprocess.CompletedProcess[bytes] = subprocess.run(
        [sys.executable, str(script)] + args,
        cwd=root
    )
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
