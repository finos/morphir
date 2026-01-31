#!/usr/bin/env python3
# #MISE description="Validate JSON example files against their schemas"
# #USAGE flag "--verbose" help="Show detailed validation output"
# #USAGE flag "--json" help="Output results as JSON"
"""
Validate Morphir IR example files against their respective schemas.

This script:
1. Finds JSON example files in known locations
2. Auto-detects schema version from formatVersion field
3. Validates against the appropriate schema (v1-v4)
4. Reports validation errors with file paths and details
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


def find_example_files(root: Path) -> list[Path]:
    """Find all JSON example files to validate."""
    example_files: list[Path] = []

    # Documentation examples
    doc_examples = root / "docs" / "spec" / "ir" / "schemas"
    if doc_examples.exists():
        example_files.extend(doc_examples.rglob("*.json"))

    # Static IR examples
    static_examples = root / "website" / "static" / "ir" / "examples"
    if static_examples.exists():
        example_files.extend(static_examples.rglob("*.json"))

    # Exclude manifest files (index.json)
    example_files = [f for f in example_files if f.name != "index.json"]

    return sorted(example_files)


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
    example_files = find_example_files(root)

    if not example_files:
        print("No example files found to validate.")
        return 0

    results: list[dict[str, Any]] = []
    errors = 0

    for file_path in example_files:
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
        print(f"\nValidated {len(example_files)} files, {errors} errors")

    return 1 if errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
