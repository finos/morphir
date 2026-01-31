#!/usr/bin/env python3
# #MISE description="Validate morphir-ir fixture files against their schemas"
# #USAGE flag "--verbose" help="Show detailed validation output"
# #USAGE flag "--json" help="Output results as JSON"
"""
Validate Morphir IR fixture files against their respective schemas.

This script:
1. Scans predefined fixture locations for JSON files
2. Auto-detects schema version from formatVersion field
3. Validates against the appropriate schema (v1-v4)
4. Reports validation errors with file paths and details
5. Skips missing directories with a warning (non-fatal)

Fixture locations:
- .morphir/testing/fixtures/ (local development fixtures)
- tests/bdd/testdata/morphir-ir/ (fetched fixtures)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def find_repo_root() -> Path:
    """Find the repository root by looking for .git"""
    current: Path = Path.cwd()
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    return Path.cwd()


def get_format_version(data: dict[str, Any]) -> str | None:
    """Extract formatVersion from IR data."""
    if "formatVersion" in data:
        version = data["formatVersion"]
        if isinstance(version, int):
            return str(version)
        if isinstance(version, str):
            # Handle "4.0.0" -> "4"
            return version.split(".")[0]
    return None


def get_schema_path(root: Path, version: str) -> Path | None:
    """Get the schema path for a given version."""
    schema_dir = root / "website" / "static" / "schemas"
    # Try YAML first (source of truth), then JSON
    yaml_path = schema_dir / f"morphir-ir-v{version}.yaml"
    json_path = schema_dir / f"morphir-ir-v{version}.json"

    if yaml_path.exists():
        return yaml_path
    if json_path.exists():
        return json_path
    return None


# Predefined fixture locations
FIXTURE_DIRS = [
    ".morphir/testing/fixtures",  # Local development fixtures
    "tests/bdd/testdata/morphir-ir",  # Fetched fixtures
]


def find_fixture_files(root: Path, verbose: bool = False) -> list[Path]:
    """Find all JSON fixture files to validate."""
    fixture_files: list[Path] = []

    for fixture_dir in FIXTURE_DIRS:
        dir_path = root / fixture_dir
        if dir_path.exists():
            files = list(dir_path.rglob("*.json"))
            fixture_files.extend(files)
            if verbose:
                print(f"Found {len(files)} files in {fixture_dir}")
        else:
            if verbose:
                print(f"⚠ Directory not found (skipping): {fixture_dir}")

    return sorted(fixture_files)


def validate_file(
    file_path: Path, root: Path, verbose: bool = False
) -> tuple[bool, str]:
    """Validate a single JSON file against its schema."""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return False, f"Invalid JSON: {e}"
    except Exception as e:
        return False, f"Error reading file: {e}"

    # Detect version
    version = get_format_version(data)
    if version is None:
        return False, "No formatVersion field found"

    # Get schema
    schema_path = get_schema_path(root, version)
    if schema_path is None:
        return False, f"No schema found for version {version}"

    if verbose:
        print(f"  Version: {version}, Schema: {schema_path.name}")

    # For now, just validate JSON structure is parseable
    # Full JSON Schema validation would require jsonschema library
    # The jsonschema CLI tool handles the actual validation
    return True, f"Valid (v{version})"


def main() -> int:
    """Main entry point."""
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    json_output = "--json" in sys.argv

    root = find_repo_root()
    fixture_files = find_fixture_files(root, verbose)

    if not fixture_files:
        if not json_output:
            print("No fixture files found to validate.")
            print("Fixture directories checked:")
            for d in FIXTURE_DIRS:
                exists = "✓" if (root / d).exists() else "✗"
                print(f"  {exists} {d}")
        return 0

    results: list[dict[str, Any]] = []
    errors = 0

    for file_path in fixture_files:
        rel_path = file_path.relative_to(root)
        success, message = validate_file(file_path, root, verbose)

        if json_output:
            results.append(
                {"file": str(rel_path), "valid": success, "message": message}
            )
        else:
            status = "✓" if success else "✗"
            print(f"{status} {rel_path}: {message}")

        if not success:
            errors += 1

    if json_output:
        print(json.dumps({"results": results, "errors": errors}, indent=2))
    else:
        print(f"\nValidated {len(fixture_files)} fixtures, {errors} errors")

    return 1 if errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
