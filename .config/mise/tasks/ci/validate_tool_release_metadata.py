#!/usr/bin/env python3
"""Validate the signed tool release metadata schema and fixture descriptors."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


def run(*arguments: str) -> None:
    result = subprocess.run(arguments, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(arguments)} exited with {result.returncode}")


def main() -> int:
    root = Path(__file__).resolve().parents[4]
    spec = root / "docs" / "spec" / "tool-release-metadata"
    schema = root / "website" / "static" / "schemas" / "tool-release-v1.schema.json"
    fixture_path = spec / "fixtures" / "v1" / "conformance.json"
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))

    run("jsonschema", "fmt", "--check", str(schema))
    run("jsonschema", "metaschema", str(schema))
    run("jsonschema", "lint", str(schema))

    trusted_targets = fixture["metadata"]["targets"]["signed"]["targets"]
    target_files = fixture["targetFiles"]
    release_paths = sorted(
        path
        for path, target in trusted_targets.items()
        if target["custom"]["morphir"]["kind"] == "tool-release"
    )
    if not release_paths:
        raise RuntimeError("the conformance fixture contains no tool release descriptors")

    with tempfile.TemporaryDirectory(prefix="morphir-tool-metadata-") as directory:
        temporary = Path(directory)
        for index, target_path in enumerate(release_paths):
            descriptor = json.loads(target_files[target_path])
            descriptor_path = temporary / f"release-{index}.json"
            descriptor_path.write_text(
                json.dumps(descriptor, separators=(",", ":")), encoding="utf-8"
            )
            run("jsonschema", "validate", str(schema), str(descriptor_path))

    print(f"Validated {len(release_paths)} authenticated tool release descriptors")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyError, json.JSONDecodeError, OSError, RuntimeError) as error:
        print(f"Tool release metadata validation failed: {error}", file=sys.stderr)
        sys.exit(1)
