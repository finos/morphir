#!/usr/bin/env python3
"""
Build MoonBit packages in morphir-moonbit.

This script builds packages in the morphir-moonbit submodule
for both WASM and WASM-GC targets.

Usage:
    python build_morphir_moonbit.py [package...]

Arguments:
    package  Optional package names to build. If not provided, builds all packages.
             Valid packages: morphir-sdk, morphir-core, morphir-moonbit-bindings

Examples:
    python build_morphir_moonbit.py                     # Build all packages
    python build_morphir_moonbit.py morphir-sdk        # Build only morphir-sdk
    python build_morphir_moonbit.py morphir-sdk morphir-core  # Build specific packages
"""

import subprocess
import sys
from pathlib import Path

ALL_PACKAGES = ["morphir-sdk", "morphir-core", "morphir-moonbit-bindings"]
TARGETS = ["wasm", "wasm-gc"]


def run_moon_command(cmd: list[str], cwd: Path) -> bool:
    """Run a moon command and return success status."""
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  Error: {result.stderr}", file=sys.stderr)
        if result.stdout:
            print(f"  Output: {result.stdout}", file=sys.stderr)
        return False
    return True


def main() -> int:
    """Build MoonBit packages."""
    repo_root = Path(__file__).resolve().parents[4]
    moonbit_dir = repo_root / "ecosystem" / "morphir-moonbit"
    pkgs_dir = moonbit_dir / "pkgs"

    if not pkgs_dir.exists():
        print(f"Error: Packages directory not found: {pkgs_dir}", file=sys.stderr)
        return 1

    # Determine which packages to build
    if len(sys.argv) > 1:
        packages = sys.argv[1:]
        # Validate package names
        invalid = [p for p in packages if p not in ALL_PACKAGES]
        if invalid:
            print(f"Error: Unknown package(s): {', '.join(invalid)}", file=sys.stderr)
            print(f"Valid packages: {', '.join(ALL_PACKAGES)}", file=sys.stderr)
            return 1
    else:
        packages = ALL_PACKAGES

    print(f"Building MoonBit packages: {', '.join(packages)}...")

    errors = []
    for pkg in packages:
        pkg_dir = pkgs_dir / pkg
        if not pkg_dir.exists():
            print(f"  Skipping {pkg} (not found)")
            continue

        print(f"  Building {pkg}...")

        for target in TARGETS:
            print(f"    Target: {target}")
            if not run_moon_command(["moon", "build", "--target", target], pkg_dir):
                errors.append(f"{pkg} ({target})")

    if errors:
        print(f"\nBuild failed for: {', '.join(errors)}", file=sys.stderr)
        return 1

    print("\nAll MoonBit packages built successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
