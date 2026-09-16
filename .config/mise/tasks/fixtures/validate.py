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
5. Fails when no fixture file is found at all, so a moved directory cannot
   turn the check into a silent pass

Fixture locations:
- tests/bdd/fixtures/ir/ (tracked IR fixtures, one directory per format version)
- .morphir/testing/fixtures/ (local development fixtures, optional)
"""

from __future__ import annotations

import json
import subprocess
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
    "tests/bdd/fixtures/ir",  # Tracked IR fixtures
    ".morphir/testing/fixtures",  # Local development fixtures (optional)
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
                print(f"warning: directory not found (skipping): {fixture_dir}")

    return sorted(fixture_files)


def is_fragment_collection(file_path: Path) -> bool:
    """True for a node-example collection: an object with neither a
    formatVersion nor a distribution member. An IR document always carries a
    distribution, so one that merely lost its formatVersion is still validated
    and fails on it."""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        # Unreadable or invalid JSON is reported by validate_file.
        return False
    return (
        isinstance(data, dict)
        and "formatVersion" not in data
        and "distribution" not in data
    )


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

    # Run jsonschema CLI for actual validation
    try:
        # We use jsonschema CLI which is part of our mise configuration
        result = subprocess.run(
            ["jsonschema", "validate", str(schema_path), str(file_path)],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return True, f"Valid (v{version})"
        else:
            # Clean up error message (take first few lines of stderr)
            error_msg = result.stderr.strip().split("\n")[0]
            return False, f"Schema validation failed: {error_msg}"
    except FileNotFoundError:
        return False, "jsonschema CLI not found. Please run 'mise install'."
    except Exception as e:
        return False, f"Validation error: {e}"


def main() -> int:
    """Main entry point."""
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    json_output = "--json" in sys.argv

    root = find_repo_root()
    fixture_files = find_fixture_files(root, verbose)

    if not fixture_files:
        # Nothing validated is a failure: a moved or misspelled directory must
        # not turn this check into a silent pass.
        checked = {d: (root / d).exists() for d in FIXTURE_DIRS}
        if json_output:
            print(json.dumps({"results": [], "errors": 1, "validated": 0, "error": "no fixture files found", "directories": checked}, indent=2))
        else:
            print("No fixture files found to validate.")
            print("Fixture directories checked:")
            for d, exists in checked.items():
                print(f"  {d}: {'present' if exists else 'missing'}")
        return 1

    results: list[dict[str, Any]] = []
    errors = 0
    validated = 0

    for file_path in fixture_files:
        rel_path = file_path.relative_to(root)
        # A fixture directory also holds fragment collections (node examples
        # with neither formatVersion nor distribution) that are not IR documents. There is no
        # schema to hold them to; say so rather than counting them as failures
        # or silently passing them. Anything else is validated, including a
        # document that lost its formatVersion.
        if is_fragment_collection(file_path):
            if json_output:
                results.append({"file": str(rel_path), "valid": None, "message": "skipped: fragment collection, not an IR document"})
            else:
                print(f"skip {rel_path}: fragment collection, not an IR document")
            continue
        validated += 1
        success, message = validate_file(file_path, root, verbose)

        if json_output:
            results.append(
                {"file": str(rel_path), "valid": success, "message": message}
            )
        else:
            # ASCII markers: a Windows console with a cp1252 code page cannot
            # print the check-mark glyphs.
            status = "ok  " if success else "FAIL"
            print(f"{status} {rel_path}: {message}")

        if not success:
            errors += 1

    if validated == 0:
        if json_output:
            print(json.dumps({"results": results, "errors": 1, "validated": 0, "error": "no IR document found among the fixtures"}, indent=2))
        else:
            print("No IR document found among the fixtures; nothing was validated.")
        return 1

    if json_output:
        print(json.dumps({"results": results, "errors": errors, "validated": validated}, indent=2))
    else:
        print(f"\nValidated {validated} of {len(fixture_files)} fixtures, {errors} errors")

    return 1 if errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
