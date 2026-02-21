#!/usr/bin/env python3
"""
Run tests for MoonBit packages in morphir-moonbit.

This script runs tests for packages in the morphir-moonbit submodule.

Usage:
    python test_morphir_moonbit.py [package...]

Arguments:
    package  Optional package names to test. If not provided, tests all packages.
             Valid packages: morphir-sdk, morphir-core, morphir-moonbit-bindings

Examples:
    python test_morphir_moonbit.py                     # Test all packages
    python test_morphir_moonbit.py morphir-sdk        # Test only morphir-sdk
    python test_morphir_moonbit.py morphir-sdk morphir-core  # Test specific packages
"""

import subprocess
import sys
from pathlib import Path

ALL_PACKAGES = ["morphir-sdk", "morphir-core", "morphir-moonbit-bindings"]


def run_moon_command(cmd: list[str], cwd: Path) -> bool:
    """Run a moon command and return success status."""
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  Error: {result.stderr}", file=sys.stderr)
        if result.stdout:
            print(f"  Output: {result.stdout}", file=sys.stderr)
        return False
    if result.stdout:
        print(result.stdout)
    return True


def main() -> int:
    """Run tests for MoonBit packages."""
    repo_root = Path(__file__).resolve().parents[4]
    moonbit_dir = repo_root / "ecosystem" / "morphir-moonbit"
    pkgs_dir = moonbit_dir / "pkgs"

    if not pkgs_dir.exists():
        print(f"Error: Packages directory not found: {pkgs_dir}", file=sys.stderr)
        return 1

    # Determine which packages to test
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

    print(f"Running MoonBit tests: {', '.join(packages)}...")

    errors = []
    for pkg in packages:
        pkg_dir = pkgs_dir / pkg
        if not pkg_dir.exists():
            print(f"  Skipping {pkg} (not found)")
            continue

        print(f"  Testing {pkg}...")
        if not run_moon_command(["moon", "test"], pkg_dir):
            errors.append(pkg)

    if errors:
        print(f"\nTests failed for: {', '.join(errors)}", file=sys.stderr)
        return 1

    print("\nAll MoonBit tests passed!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
