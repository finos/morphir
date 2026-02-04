#!/usr/bin/env python3
"""
Add a new git submodule under ecosystem/.

Usage: mise run submodules:add -- <name> [url]
  name: Submodule directory name (e.g. morphir-go, morphir-elm). Required.
  url:  Clone URL. If omitted, defaults to https://github.com/finos/<name>.git

Example:
  mise run submodules:add -- morphir-go
  mise run submodules:add -- morphir-elm https://github.com/finos/morphir-elm.git
"""

from __future__ import annotations

import os
import re
import subprocess
import sys


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--"]
    if not args:
        print("Usage: mise run submodules:add -- <name> [url]", file=sys.stderr)
        print("  name: submodule directory under ecosystem/ (e.g. morphir-go)", file=sys.stderr)
        print("  url:  optional; defaults to https://github.com/finos/<name>.git", file=sys.stderr)
        return 1

    name = args[0].strip()
    if not name:
        print("Error: name cannot be empty", file=sys.stderr)
        return 1

    # Basic sanity: name should look like a repo name (no path separators, no scheme)
    if re.search(r"[/\\:]", name) or name.startswith("."):
        print("Error: name should be a simple directory name (e.g. morphir-go)", file=sys.stderr)
        return 1

    url = args[1].strip() if len(args) > 1 else f"https://github.com/finos/{name}.git"

    repo_root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=False,
    )
    if repo_root.returncode != 0:
        print("Error: must run from inside a git repository", file=sys.stderr)
        return 1

    root = repo_root.stdout.strip()
    ecosystem_dir = os.path.join(root, "ecosystem")
    path = os.path.join(ecosystem_dir, name)

    if not os.path.isdir(ecosystem_dir):
        print(f"Error: ecosystem directory not found: {ecosystem_dir}", file=sys.stderr)
        return 1

    if os.path.exists(path):
        print(f"Error: path already exists: {path}", file=sys.stderr)
        return 1

    cmd = ["git", "submodule", "add", url, f"ecosystem/{name}"]
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=root)
    if result.returncode != 0:
        return result.returncode

    print("")
    print("Next: add the new submodule to ecosystem/README.md and ecosystem/AGENTS.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
