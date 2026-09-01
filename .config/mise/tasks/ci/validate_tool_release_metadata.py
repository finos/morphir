#!/usr/bin/env python3
"""Validate the signed tool release metadata schema and fixture descriptors."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path


def run(*arguments: str) -> None:
    result = subprocess.run(arguments, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(arguments)} exited with {result.returncode}")


def assert_schema_rejects(schema: Path, descriptor: dict, label: str, path: Path) -> None:
    path.write_text(json.dumps(descriptor, separators=(",", ":")), encoding="utf-8")
    result = subprocess.run(
        ["jsonschema", "validate", str(schema), str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        raise RuntimeError(f"schema accepted invalid {label}")


def validate_application(root: Path, *descriptors: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "cargo",
            "run",
            "--quiet",
            "--locked",
            "--package",
            "morphir",
            "--example",
            "validate-tool-release-metadata",
            "--",
            *(str(descriptor) for descriptor in descriptors),
        ],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )


def assert_application_rejects(
    root: Path, descriptor: dict, label: str, path: Path
) -> None:
    path.write_text(json.dumps(descriptor, separators=(",", ":")), encoding="utf-8")
    result = validate_application(root, path)
    if result.returncode == 0:
        raise RuntimeError(f"application validator accepted invalid {label}")


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
        descriptor_paths = []
        for index, target_path in enumerate(release_paths):
            descriptor = json.loads(target_files[target_path])
            descriptor_path = temporary / f"release-{index}.json"
            descriptor_path.write_text(
                json.dumps(descriptor, separators=(",", ":")), encoding="utf-8"
            )
            run("jsonschema", "validate", str(schema), str(descriptor_path))
            descriptor_paths.append(descriptor_path)

        application_result = validate_application(root, *descriptor_paths)
        if application_result.returncode != 0:
            raise RuntimeError(
                "application validation failed: "
                + (application_result.stderr.strip() or application_result.stdout.strip())
            )

        descriptor = next(
            candidate
            for target_path in release_paths
            if (candidate := json.loads(target_files[target_path]))["artifacts"]
        )
        invalid = deepcopy(descriptor)
        invalid["compatibility"]["morphirCli"] = "not-a-version-requirement"
        assert_application_rejects(
            root,
            invalid,
            "Morphir CLI version requirement",
            temporary / "invalid-morphir-cli-requirement.json",
        )

        for label, field in [
            ("target path with a trailing empty segment", "targetPath"),
            ("archive entry point with a trailing empty segment", "entryPoint"),
            ("launch path with a trailing empty segment", "path"),
        ]:
            invalid = deepcopy(descriptor)
            artifact = invalid["artifacts"][0]
            if field == "targetPath":
                artifact[field] += "/"
            elif field == "entryPoint":
                artifact["archive"][field] += "/"
            else:
                artifact["launch"][field] += "/"
            assert_schema_rejects(
                schema,
                invalid,
                label,
                temporary / f"invalid-{field}.json",
            )

        for line_name, line_terminator in [
            ("lf", "\n"),
            ("cr", "\r"),
            ("line-separator", "\u2028"),
            ("paragraph-separator", "\u2029"),
        ]:
            for label, field in [
                ("target path", "targetPath"),
                ("archive entry point", "entryPoint"),
                ("launch path", "path"),
            ]:
                invalid = deepcopy(descriptor)
                artifact = invalid["artifacts"][0]
                invalid_path = f"artifacts/file{line_terminator}../escape"
                if field == "targetPath":
                    artifact[field] = invalid_path
                elif field == "entryPoint":
                    artifact["archive"][field] = invalid_path
                else:
                    artifact["launch"][field] = invalid_path
                assert_schema_rejects(
                    schema,
                    invalid,
                    f"{label} containing {line_name}",
                    temporary / f"invalid-{field}-{line_name}.json",
                )

    print(f"Validated {len(release_paths)} authenticated tool release descriptors")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyError, json.JSONDecodeError, OSError, RuntimeError) as error:
        print(f"Tool release metadata validation failed: {error}", file=sys.stderr)
        sys.exit(1)
