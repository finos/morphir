#!/usr/bin/env python3
"""
Prepare Cargo workspace for morphir CLI build.

This script modifies Cargo.toml to exclude morphir-live (which has conflicting
dependencies) and regenerates the lockfile for CLI-only builds.

Usage:
    python prepare_cli_workspace.py
"""

import re
import subprocess
import sys
from pathlib import Path


def main() -> int:
    """Prepare workspace for CLI-only build."""
    repo_root = Path(__file__).resolve().parents[4]
    cargo_toml = repo_root / "Cargo.toml"
    cargo_lock = repo_root / "Cargo.lock"

    print("Preparing workspace for morphir CLI build...")

    # Read current Cargo.toml
    content = cargo_toml.read_text()

    # Update members to only include morphir crate
    content = re.sub(
        r'members\s*=\s*\["crates/\*"\]',
        'members = ["crates/morphir"]',
        content,
    )

    # Update default-members to only include morphir
    content = re.sub(
        r'default-members\s*=\s*\["crates/morphir-live",\s*"crates/morphir"\]',
        'default-members = ["crates/morphir"]',
        content,
    )

    # Write modified Cargo.toml
    cargo_toml.write_text(content)
    print("  Updated Cargo.toml to exclude morphir-live")

    # Remove existing lockfile
    if cargo_lock.exists():
        cargo_lock.unlink()
        print("  Removed existing Cargo.lock")

    # Generate fresh lockfile
    print("  Generating fresh lockfile...")
    result = subprocess.run(
        ["cargo", "generate-lockfile"],
        cwd=repo_root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error generating lockfile: {result.stderr}", file=sys.stderr)
        return 1

    # Update extism to latest compatible version
    print("  Updating extism to latest compatible version...")
    result = subprocess.run(
        ["cargo", "update", "-p", "extism"],
        cwd=repo_root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Warning: Could not update extism: {result.stderr}", file=sys.stderr)
        # Don't fail - extism update is optional

    print("Workspace prepared for CLI build!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
