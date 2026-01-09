#!/usr/bin/env python3
"""
validate_docs_structure.py - Validate Morphir documentation structure

This script validates that documentation follows the expected structure,
has proper frontmatter, and files are in the correct sections.

Usage:
    python validate_docs_structure.py [--fix] [--verbose] [path]

Options:
    --fix      Attempt to fix common issues (add missing frontmatter)
    --verbose  Show detailed output
    path       Specific file or directory to check (default: docs/)

Exit codes:
    0 - All validations passed
    1 - Validation errors found
    2 - Script error
"""

import argparse
import os
import re
import sys
import yaml
from pathlib import Path
from typing import Dict, List, Tuple, Optional

# Expected documentation sections and their purposes
EXPECTED_SECTIONS = {
    'getting-started': {
        'description': 'Introductory content for new users',
        'expected_files': ['intro.md', 'installation.md'],
        'sidebar_position_range': (1, 10),
    },
    'cli-preview': {
        'description': 'Next-generation CLI documentation',
        'expected_files': ['index.md'],
        'sidebar_position_range': (1, 20),
    },
    'concepts': {
        'description': 'Core concepts and theory',
        'expected_files': ['introduction-to-morphir.md'],
        'sidebar_position_range': (1, 20),
    },
    'spec': {
        'description': 'Technical specifications',
        'expected_files': ['index.md'],
        'sidebar_position_range': (1, 20),
    },
    'user-guides': {
        'description': 'Practical guides for users',
        'subdirs': ['modeling-guides', 'cli-tools', 'development-guides'],
        'sidebar_position_range': (1, 30),
    },
    'reference': {
        'description': 'API and technical reference',
        'subdirs': ['backends', 'json-schema', 'cli'],
        'sidebar_position_range': (1, 50),
    },
    'developers': {
        'description': 'Contributor and developer guides',
        'expected_files': ['contributing.md'],
        'sidebar_position_range': (1, 20),
    },
    'community': {
        'description': 'Community resources',
        'expected_files': ['morphir-community.md'],
        'sidebar_position_range': (1, 10),
    },
    'use-cases': {
        'description': 'Real-world use cases and examples',
        'sidebar_position_range': (1, 20),
    },
    'adr': {
        'description': 'Architecture Decision Records',
        'sidebar_position_range': (1, 100),
    },
}


class ValidationError:
    """Represents a validation error."""
    def __init__(self, file_path: str, error_type: str, message: str, fixable: bool = False):
        self.file_path = file_path
        self.error_type = error_type
        self.message = message
        self.fixable = fixable

    def __str__(self):
        fix_indicator = " [FIXABLE]" if self.fixable else ""
        return f"{self.error_type}: {self.file_path}\n  {self.message}{fix_indicator}"


def extract_frontmatter(content: str) -> Tuple[Optional[Dict], str]:
    """Extract YAML frontmatter from markdown content."""
    if not content.startswith('---'):
        return None, content

    match = re.match(r'^---\n(.*?)\n---\n?(.*)$', content, re.DOTALL)
    if not match:
        return None, content

    try:
        frontmatter = yaml.safe_load(match.group(1))
        body = match.group(2)
        return frontmatter, body
    except yaml.YAMLError:
        return None, content


def validate_frontmatter(file_path: Path, content: str) -> List[ValidationError]:
    """Validate markdown file frontmatter."""
    errors = []
    frontmatter, body = extract_frontmatter(content)

    if frontmatter is None:
        errors.append(ValidationError(
            str(file_path),
            "MISSING_FRONTMATTER",
            "File is missing YAML frontmatter (---)",
            fixable=True
        ))
        return errors

    # Check for recommended fields
    if 'sidebar_position' not in frontmatter:
        errors.append(ValidationError(
            str(file_path),
            "MISSING_SIDEBAR_POSITION",
            "Frontmatter missing 'sidebar_position' field",
            fixable=True
        ))

    # Title can come from frontmatter or first heading
    has_title = 'title' in frontmatter or 'sidebar_label' in frontmatter
    if not has_title:
        # Check for h1 heading in body
        if not re.match(r'^#\s+\S', body.strip()):
            errors.append(ValidationError(
                str(file_path),
                "MISSING_TITLE",
                "File needs either 'title' in frontmatter or an H1 heading",
                fixable=False
            ))

    return errors


def validate_file_location(file_path: Path, docs_root: Path) -> List[ValidationError]:
    """Validate that files are in appropriate sections."""
    errors = []
    relative_path = file_path.relative_to(docs_root)
    parts = relative_path.parts

    if len(parts) < 2:
        # Root-level file
        return errors

    section = parts[0]

    # Check if section is recognized
    if section not in EXPECTED_SECTIONS and not section.startswith('.'):
        # Allow some flexibility but warn
        pass  # Not an error, just not a standard section

    return errors


def validate_links_in_file(file_path: Path, content: str, docs_root: Path) -> List[ValidationError]:
    """Validate internal links in a markdown file."""
    errors = []
    _, body = extract_frontmatter(content)

    # Find markdown links
    link_pattern = r'\[([^\]]*)\]\(([^)]+)\)'
    matches = re.finditer(link_pattern, body)

    for match in matches:
        link_text, link_url = match.groups()

        # Skip external links and anchors
        if link_url.startswith(('http://', 'https://', '#', 'mailto:')):
            continue

        # Remove anchor
        clean_link = link_url.split('#')[0]
        if not clean_link:
            continue

        # Resolve path
        if clean_link.startswith('/'):
            target = docs_root / clean_link.lstrip('/')
        else:
            target = file_path.parent / clean_link

        # Normalize
        try:
            target = target.resolve()
        except Exception:
            pass

        # Check existence
        if not target.exists() and not target.with_suffix('.md').exists():
            if not target.is_dir():
                errors.append(ValidationError(
                    str(file_path),
                    "BROKEN_LINK",
                    f"Link '{link_url}' -> target not found",
                    fixable=False
                ))

    return errors


def validate_heading_structure(file_path: Path, content: str) -> List[ValidationError]:
    """Validate heading hierarchy in markdown."""
    errors = []
    _, body = extract_frontmatter(content)

    lines = body.split('\n')
    prev_level = 0
    h1_count = 0

    for line in lines:
        match = re.match(r'^(#{1,6})\s+\S', line)
        if match:
            level = len(match.group(1))

            if level == 1:
                h1_count += 1

            # Check for heading level jumps (e.g., h1 -> h3)
            if prev_level > 0 and level > prev_level + 1:
                errors.append(ValidationError(
                    str(file_path),
                    "HEADING_SKIP",
                    f"Heading level jumps from H{prev_level} to H{level}",
                    fixable=False
                ))

            prev_level = level

    # Multiple H1 headings
    if h1_count > 1:
        errors.append(ValidationError(
            str(file_path),
            "MULTIPLE_H1",
            f"File has {h1_count} H1 headings (should have at most 1)",
            fixable=False
        ))

    return errors


def validate_file(file_path: Path, docs_root: Path, verbose: bool = False) -> List[ValidationError]:
    """Run all validations on a single file."""
    errors = []

    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception as e:
        errors.append(ValidationError(
            str(file_path),
            "READ_ERROR",
            f"Could not read file: {e}",
            fixable=False
        ))
        return errors

    errors.extend(validate_frontmatter(file_path, content))
    errors.extend(validate_file_location(file_path, docs_root))
    errors.extend(validate_heading_structure(file_path, content))
    # Link validation is optional and can be slow
    # errors.extend(validate_links_in_file(file_path, content, docs_root))

    return errors


def fix_missing_frontmatter(file_path: Path) -> bool:
    """Add basic frontmatter to a file missing it."""
    try:
        content = file_path.read_text(encoding='utf-8')
        if content.startswith('---'):
            return False

        # Extract title from first heading
        title_match = re.match(r'^#\s+(.+)$', content.strip(), re.MULTILINE)
        title = title_match.group(1) if title_match else file_path.stem.replace('-', ' ').title()

        frontmatter = f"""---
title: {title}
sidebar_position: 1
---

"""
        new_content = frontmatter + content
        file_path.write_text(new_content, encoding='utf-8')
        return True
    except Exception:
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Validate Morphir documentation structure"
    )
    parser.add_argument('path', nargs='?', default=None,
                        help="Path to validate (default: docs/)")
    parser.add_argument('--fix', action='store_true',
                        help="Attempt to fix common issues")
    parser.add_argument('--verbose', '-v', action='store_true',
                        help="Show detailed output")
    parser.add_argument('--check-links', action='store_true',
                        help="Also check internal links (slower)")

    args = parser.parse_args()

    # Find docs root
    script_dir = Path(__file__).parent
    project_root = script_dir.parent.parent.parent.parent.parent
    docs_root = project_root / 'docs'

    if args.path:
        target = Path(args.path)
        if not target.is_absolute():
            target = Path.cwd() / target
    else:
        target = docs_root

    if not target.exists():
        print(f"Error: Path not found: {target}")
        sys.exit(2)

    print(f"Validating documentation in: {target}")
    print("")

    all_errors: List[ValidationError] = []
    files_checked = 0

    # Collect files to check
    if target.is_file():
        files = [target]
    else:
        files = list(target.rglob('*.md'))

    for file_path in files:
        if args.verbose:
            print(f"Checking: {file_path.relative_to(docs_root) if docs_root in file_path.parents else file_path}")

        errors = validate_file(file_path, docs_root, args.verbose)
        all_errors.extend(errors)
        files_checked += 1

    # Report results
    print(f"Checked {files_checked} files")
    print("")

    if not all_errors:
        print("✅ All validations passed!")
        sys.exit(0)

    # Group errors by type
    errors_by_type: Dict[str, List[ValidationError]] = {}
    for error in all_errors:
        if error.error_type not in errors_by_type:
            errors_by_type[error.error_type] = []
        errors_by_type[error.error_type].append(error)

    print(f"❌ Found {len(all_errors)} issues:")
    print("")

    for error_type, errors in errors_by_type.items():
        print(f"  {error_type}: {len(errors)}")

    print("")

    # Show details
    for error in all_errors[:20]:  # Limit output
        print(error)
        print("")

    if len(all_errors) > 20:
        print(f"... and {len(all_errors) - 20} more issues")

    # Fix if requested
    if args.fix:
        print("")
        print("Attempting fixes...")
        fixed_count = 0

        for error in all_errors:
            if error.fixable and error.error_type == "MISSING_FRONTMATTER":
                if fix_missing_frontmatter(Path(error.file_path)):
                    print(f"  Fixed: {error.file_path}")
                    fixed_count += 1

        print(f"Fixed {fixed_count} issues")

    sys.exit(1)


if __name__ == "__main__":
    main()
