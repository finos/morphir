#!/usr/bin/env python3
"""
Fetch Morphir IR fixtures from the morphir-elm project.

This script downloads morphir-ir.json files from the morphir-elm GitHub repository
for use as test fixtures in the morphir-workflows project.

Usage:
    # Download latest rentals fixture
    python fetch_morphir_ir.py

    # Download specific version
    python fetch_morphir_ir.py --version v2.100.0

    # Download to specific directory
    python fetch_morphir_ir.py --output ./fixtures

    # Download specific fixture
    python fetch_morphir_ir.py --fixture business-terms

    # List available fixtures
    python fetch_morphir_ir.py --list

    # Force re-download (ignore cache)
    python fetch_morphir_ir.py --force
"""

import argparse
import hashlib
import json
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path
from typing import Optional, Dict, List, Any

# GitHub API base URL
GITHUB_API = "https://api.github.com"
GITHUB_RAW = "https://raw.githubusercontent.com"
REPO_OWNER = "finos"
REPO_NAME = "morphir-elm"

# Known fixture locations in morphir-elm repository
FIXTURES = {
    "rentals": {
        "path": "tests-integration/cli/test-data/rentals/expected-morphir-ir.json",
        "description": "Rental request business logic example"
    },
    "rentals-v1": {
        "path": "tests-integration/cli/test-data/rentals/expected-morphir-ir-v1.json",
        "description": "Rental request example (IR format v1)"
    },
    "business-terms": {
        "path": "tests-integration/cli2-qa-test/test-data/business-terms/morphir-ir.json",
        "description": "Business terms vocabulary example"
    }
}

# Default cache directory
DEFAULT_CACHE_DIR = Path.home() / ".cache" / "morphir" / "fixtures"


def get_cache_dir() -> Path:
    """Get the cache directory, creating it if necessary."""
    cache_dir = Path(os.environ.get("MORPHIR_CACHE_DIR", DEFAULT_CACHE_DIR))
    cache_dir.mkdir(parents=True, exist_ok=True)
    return cache_dir


def get_latest_version() -> str:
    """Fetch the latest release version from GitHub."""
    url = f"{GITHUB_API}/repos/{REPO_OWNER}/{REPO_NAME}/releases/latest"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/vnd.github.v3+json"})
        with urllib.request.urlopen(req, timeout=30) as response:
            data = json.loads(response.read().decode())
            return data["tag_name"]
    except urllib.error.HTTPError as e:
        if e.code == 404:
            # No releases, use main branch
            return "main"
        raise
    except Exception as e:
        print(f"Warning: Could not fetch latest version: {e}", file=sys.stderr)
        return "main"


def get_file_hash(content: bytes) -> str:
    """Calculate SHA256 hash of content."""
    return hashlib.sha256(content).hexdigest()


def fetch_fixture(
    fixture_name: str,
    version: str = "main",
    output_dir: Optional[Path] = None,
    force: bool = False
) -> Path:
    """
    Fetch a morphir-ir fixture from GitHub.

    Args:
        fixture_name: Name of the fixture (e.g., "rentals", "business-terms")
        version: Git ref (branch, tag, or commit) to fetch from
        output_dir: Directory to save the fixture to
        force: Force re-download even if cached

    Returns:
        Path to the downloaded fixture file
    """
    if fixture_name not in FIXTURES:
        available = ", ".join(FIXTURES.keys())
        raise ValueError(f"Unknown fixture '{fixture_name}'. Available: {available}")

    fixture_info = FIXTURES[fixture_name]
    fixture_path = fixture_info["path"]

    # Determine output location
    if output_dir is None:
        output_dir = get_cache_dir() / version
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    output_file = output_dir / f"{fixture_name}.json"

    # Check cache
    if not force and output_file.exists():
        print(f"Using cached: {output_file}")
        return output_file

    # Fetch from GitHub
    url = f"{GITHUB_RAW}/{REPO_OWNER}/{REPO_NAME}/{version}/{fixture_path}"
    print(f"Fetching: {url}")

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=60) as response:
            content = response.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            raise FileNotFoundError(
                f"Fixture '{fixture_name}' not found at version '{version}'. "
                f"URL: {url}"
            )
        raise

    # Validate JSON
    try:
        ir_data = json.loads(content)
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in fixture: {e}")

    # Validate it looks like a morphir-ir file
    if "formatVersion" not in ir_data or "distribution" not in ir_data:
        raise ValueError(
            f"Downloaded file does not appear to be a valid morphir-ir.json "
            f"(missing formatVersion or distribution)"
        )

    # Write to output
    output_file.write_bytes(content)
    file_hash = get_file_hash(content)
    print(f"Downloaded: {output_file} (sha256: {file_hash[:12]}...)")

    # Write metadata
    metadata = {
        "fixture": fixture_name,
        "version": version,
        "source_url": url,
        "sha256": file_hash,
        "format_version": ir_data.get("formatVersion")
    }
    metadata_file = output_file.with_suffix(".meta.json")
    metadata_file.write_text(json.dumps(metadata, indent=2))

    return output_file


def fetch_all_fixtures(
    version: str = "main",
    output_dir: Optional[Path] = None,
    force: bool = False
) -> Dict[str, Path]:
    """Fetch all available fixtures."""
    results = {}
    for fixture_name in FIXTURES:
        try:
            path = fetch_fixture(fixture_name, version, output_dir, force)
            results[fixture_name] = path
        except Exception as e:
            print(f"Warning: Failed to fetch '{fixture_name}': {e}", file=sys.stderr)
    return results


def list_fixtures() -> None:
    """List available fixtures and their descriptions."""
    print("Available Morphir IR fixtures:")
    print()
    for name, info in FIXTURES.items():
        print(f"  {name}")
        print(f"    Path: {info['path']}")
        print(f"    Description: {info['description']}")
        print()


def list_cached(cache_dir: Optional[Path] = None) -> None:
    """List cached fixtures."""
    if cache_dir is None:
        cache_dir = get_cache_dir()

    if not cache_dir.exists():
        print("No cached fixtures found.")
        return

    print(f"Cached fixtures in {cache_dir}:")
    print()

    for version_dir in sorted(cache_dir.iterdir()):
        if not version_dir.is_dir():
            continue
        print(f"  {version_dir.name}/")
        for fixture_file in sorted(version_dir.glob("*.json")):
            if fixture_file.suffix == ".json" and not fixture_file.name.endswith(".meta.json"):
                meta_file = fixture_file.with_suffix(".meta.json")
                if meta_file.exists():
                    meta = json.loads(meta_file.read_text())
                    print(f"    {fixture_file.name} (format v{meta.get('format_version', '?')})")
                else:
                    print(f"    {fixture_file.name}")


def clear_cache(cache_dir: Optional[Path] = None) -> None:
    """Clear the fixture cache."""
    if cache_dir is None:
        cache_dir = get_cache_dir()

    if not cache_dir.exists():
        print("Cache is already empty.")
        return

    import shutil
    shutil.rmtree(cache_dir)
    print(f"Cleared cache: {cache_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch Morphir IR fixtures from the morphir-elm project",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    parser.add_argument(
        "--fixture", "-f",
        help="Specific fixture to download (default: rentals)"
    )
    parser.add_argument(
        "--version", "-v",
        help="Git ref to fetch from (branch, tag, or commit). Default: latest release"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        help="Output directory for fixtures"
    )
    parser.add_argument(
        "--all", "-a",
        action="store_true",
        help="Download all available fixtures"
    )
    parser.add_argument(
        "--list", "-l",
        action="store_true",
        help="List available fixtures"
    )
    parser.add_argument(
        "--cached",
        action="store_true",
        help="List cached fixtures"
    )
    parser.add_argument(
        "--clear-cache",
        action="store_true",
        help="Clear the fixture cache"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Force re-download even if cached"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON"
    )

    args = parser.parse_args()

    # Handle listing commands
    if args.list:
        list_fixtures()
        return 0

    if args.cached:
        list_cached()
        return 0

    if args.clear_cache:
        clear_cache()
        return 0

    # Determine version
    version = args.version
    if version is None:
        print("Determining latest version...", file=sys.stderr)
        version = get_latest_version()
        print(f"Using version: {version}", file=sys.stderr)

    try:
        if args.all:
            results = fetch_all_fixtures(version, args.output, args.force)
            if args.json:
                output = {name: str(path) for name, path in results.items()}
                print(json.dumps(output, indent=2))
            else:
                print(f"\nDownloaded {len(results)} fixture(s)")
        else:
            fixture_name = args.fixture or "rentals"
            path = fetch_fixture(fixture_name, version, args.output, args.force)
            if args.json:
                print(json.dumps({"path": str(path)}, indent=2))
            else:
                print(f"\nFixture ready: {path}")

        return 0

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
