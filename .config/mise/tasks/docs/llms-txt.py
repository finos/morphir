#!/usr/bin/env python3
# #MISE description="Generate llms.txt and llms-full.txt files"
# #MISE alias="llms"
# #USAGE flag "--compact-only" help="Generate only llms.txt (compact version)"
# #USAGE flag "--full-only" help="Generate only llms-full.txt (full version)"
# #USAGE flag "--dry-run" help="Preview without writing files"
"""
Wrapper for llms.txt generation script.
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
    script: Path = root / ".claude" / "skills" / "technical-writer" / "scripts" / "generate_llms_txt.py"

    if not script.exists():
        print(f"Error: Script not found: {script}", file=sys.stderr)
        return 1

    result: subprocess.CompletedProcess[bytes] = subprocess.run(
        [sys.executable, str(script)] + sys.argv[1:],
        cwd=root
    )
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
