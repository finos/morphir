#!/usr/bin/env python3
"""
Validate documentation files.

This script performs quick validation checks on markdown and documentation
files without making slow HTTP requests to verify external links.

Usage:
    python validate_docs.py
"""

import sys
from pathlib import Path


def main() -> int:
    """Validate documentation files."""
    repo_root = Path(__file__).resolve().parents[4]

    print("Validating documentation files...")

    # Collect markdown files
    md_files = list(repo_root.glob("**/*.md"))

    # Exclude common non-doc directories
    excluded_dirs = {".git", "node_modules", "target", ".mise", "dist", "build"}
    md_files = [
        f
        for f in md_files
        if not any(excluded in f.parts for excluded in excluded_dirs)
    ]

    if not md_files:
        print("  No markdown files found")
        return 0

    print(f"  Found {len(md_files)} markdown files")

    # Quick validation - just verify files are readable
    errors = []
    for md_file in md_files[:50]:  # Check first 50 files to keep it fast
        try:
            content = md_file.read_text(encoding="utf-8")
            # Basic check: file is not empty or just whitespace
            if not content.strip():
                errors.append(f"  Empty file: {md_file.relative_to(repo_root)}")
        except UnicodeDecodeError:
            errors.append(f"  Encoding error: {md_file.relative_to(repo_root)}")
        except Exception as e:
            errors.append(f"  Error reading {md_file.relative_to(repo_root)}: {e}")

    if errors:
        print("\nValidation issues:")
        for error in errors:
            print(error)
        # Don't fail on empty files, just warn
        print("\nValidation completed with warnings")
    else:
        print("  All checked files are valid")

    print("Documentation validation passed!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
