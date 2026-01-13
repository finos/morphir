#!/usr/bin/env python3
# #MISE description="Fetch morphir-ir fixtures from morphir-elm"
# #USAGE flag "--all" help="Fetch all available fixtures"
# #USAGE flag "--list" help="List available fixtures"
# #USAGE flag "--cached" help="Use cached fixtures if available"
# #USAGE flag "--clear-cache" help="Clear the fixture cache"
# #USAGE arg "[fixture]" help="Specific fixture to fetch (e.g., rentals)"
"""
Wrapper for morphir-ir fixture fetching.
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
    script: Path = root / ".claude" / "skills" / "morphir-developer" / "scripts" / "fetch_morphir_ir.py"

    if not script.exists():
        print(f"Error: Script not found: {script}", file=sys.stderr)
        return 1

    # Default output directory
    default_args: list[str] = ["--output", "tests/bdd/testdata/morphir-ir"]
    user_args: list[str] = sys.argv[1:]

    # Add default output if not specified
    if "--output" not in user_args and "-o" not in user_args:
        args: list[str] = user_args + default_args
    else:
        args = user_args

    result: subprocess.CompletedProcess[bytes] = subprocess.run(
        [sys.executable, str(script)] + args,
        cwd=root
    )
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
