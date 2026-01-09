#!/usr/bin/env python3
"""
Convert YAML-formatted JSON Schema files to JSON format.

This script helps keep YAML and JSON versions of Morphir IR schemas in sync.
It can convert individual files, batch convert directories, and verify that
existing JSON files match their YAML sources.

Usage:
    # Convert a single file
    python convert_schema.py morphir-ir-v3.yaml

    # Convert all YAML schemas in a directory
    python convert_schema.py --dir website/static/schemas/

    # Verify JSON files match YAML sources (no changes made)
    python convert_schema.py --verify website/static/schemas/

    # Force overwrite even if JSON is newer
    python convert_schema.py --force morphir-ir-v3.yaml

Requirements:
    pip install pyyaml
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Optional

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def yaml_to_json(yaml_path: Path, json_path: Optional[Path] = None,
                 update_id: bool = True, force: bool = False) -> dict:
    """
    Convert a YAML JSON Schema file to JSON format.

    Args:
        yaml_path: Path to the YAML schema file
        json_path: Output path for JSON file (default: same name with .json extension)
        update_id: If True, update $id to point to .json instead of .yaml
        force: If True, overwrite even if JSON file is newer

    Returns:
        dict with 'success', 'message', and optionally 'changes' keys
    """
    if not yaml_path.exists():
        return {'success': False, 'message': f"YAML file not found: {yaml_path}"}

    if json_path is None:
        json_path = yaml_path.with_suffix('.json')

    # Check if JSON is newer than YAML (skip unless forced)
    if not force and json_path.exists():
        yaml_mtime = yaml_path.stat().st_mtime
        json_mtime = json_path.stat().st_mtime
        if json_mtime > yaml_mtime:
            return {
                'success': True,
                'message': f"Skipped (JSON is newer): {json_path.name}",
                'skipped': True
            }

    # Load YAML
    try:
        with open(yaml_path, 'r', encoding='utf-8') as f:
            schema = yaml.safe_load(f)
    except yaml.YAMLError as e:
        return {'success': False, 'message': f"YAML parse error: {e}"}

    # Update $id to point to JSON file
    if update_id and '$id' in schema:
        old_id = schema['$id']
        if old_id.endswith('.yaml'):
            schema['$id'] = old_id.replace('.yaml', '.json')

    # Write JSON
    try:
        with open(json_path, 'w', encoding='utf-8') as f:
            json.dump(schema, f, indent=2, ensure_ascii=False)
            f.write('\n')  # Trailing newline
    except IOError as e:
        return {'success': False, 'message': f"Failed to write JSON: {e}"}

    return {
        'success': True,
        'message': f"Converted: {yaml_path.name} -> {json_path.name}"
    }


def verify_sync(yaml_path: Path, json_path: Optional[Path] = None) -> dict:
    """
    Verify that a JSON schema file matches its YAML source.

    Args:
        yaml_path: Path to the YAML schema file
        json_path: Path to JSON file (default: same name with .json extension)

    Returns:
        dict with 'success', 'message', and 'in_sync' keys
    """
    if json_path is None:
        json_path = yaml_path.with_suffix('.json')

    if not yaml_path.exists():
        return {'success': False, 'message': f"YAML file not found: {yaml_path}"}

    if not json_path.exists():
        return {
            'success': True,
            'message': f"JSON file missing: {json_path.name}",
            'in_sync': False,
            'issue': 'missing'
        }

    # Load both files
    try:
        with open(yaml_path, 'r', encoding='utf-8') as f:
            yaml_schema = yaml.safe_load(f)
        with open(json_path, 'r', encoding='utf-8') as f:
            json_schema = json.load(f)
    except (yaml.YAMLError, json.JSONDecodeError) as e:
        return {'success': False, 'message': f"Parse error: {e}"}

    # Normalize $id for comparison (YAML points to .yaml, JSON to .json)
    yaml_normalized = dict(yaml_schema)
    if '$id' in yaml_normalized and yaml_normalized['$id'].endswith('.yaml'):
        yaml_normalized['$id'] = yaml_normalized['$id'].replace('.yaml', '.json')

    # Compare
    if yaml_normalized == json_schema:
        return {
            'success': True,
            'message': f"In sync: {yaml_path.name}",
            'in_sync': True
        }
    else:
        return {
            'success': True,
            'message': f"Out of sync: {yaml_path.name}",
            'in_sync': False,
            'issue': 'content_mismatch'
        }


def process_directory(dir_path: Path, verify_only: bool = False, force: bool = False) -> list:
    """
    Process all YAML schema files in a directory.

    Args:
        dir_path: Directory containing schema files
        verify_only: If True, only verify sync status without making changes
        force: If True, overwrite even if JSON is newer

    Returns:
        List of result dicts for each file processed
    """
    results = []
    yaml_files = list(dir_path.glob('*.yaml'))

    for yaml_path in sorted(yaml_files):
        if verify_only:
            result = verify_sync(yaml_path)
        else:
            result = yaml_to_json(yaml_path, force=force)
        result['file'] = yaml_path.name
        results.append(result)

    return results


def main():
    parser = argparse.ArgumentParser(
        description='Convert YAML JSON Schema files to JSON format',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
    %(prog)s morphir-ir-v3.yaml
    %(prog)s --dir website/static/schemas/
    %(prog)s --verify website/static/schemas/
        '''
    )

    parser.add_argument('path', nargs='?', help='YAML file or directory to process')
    parser.add_argument('--dir', '-d', metavar='DIR',
                        help='Process all YAML files in directory')
    parser.add_argument('--verify', '-v', action='store_true',
                        help='Verify sync status only (no changes made)')
    parser.add_argument('--force', '-f', action='store_true',
                        help='Force conversion even if JSON is newer')
    parser.add_argument('--json', action='store_true',
                        help='Output results as JSON')
    parser.add_argument('--quiet', '-q', action='store_true',
                        help='Only show errors and out-of-sync files')

    args = parser.parse_args()

    # Determine what to process
    if args.dir:
        target = Path(args.dir)
        if not target.is_dir():
            print(f"Error: Not a directory: {target}", file=sys.stderr)
            sys.exit(1)
        results = process_directory(target, verify_only=args.verify, force=args.force)
    elif args.path:
        target = Path(args.path)
        if target.is_dir():
            results = process_directory(target, verify_only=args.verify, force=args.force)
        elif target.is_file():
            if args.verify:
                result = verify_sync(target)
            else:
                result = yaml_to_json(target, force=args.force)
            result['file'] = target.name
            results = [result]
        else:
            print(f"Error: Path not found: {target}", file=sys.stderr)
            sys.exit(1)
    else:
        # Default to website/static/schemas/ if it exists
        default_dir = Path('website/static/schemas')
        if default_dir.exists():
            results = process_directory(default_dir, verify_only=args.verify, force=args.force)
        else:
            parser.print_help()
            sys.exit(1)

    # Output results
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        errors = 0
        out_of_sync = 0

        for r in results:
            if not r.get('success'):
                print(f"ERROR: {r.get('file', 'unknown')}: {r['message']}", file=sys.stderr)
                errors += 1
            elif args.verify and not r.get('in_sync', True):
                print(f"OUT OF SYNC: {r['message']}")
                out_of_sync += 1
            elif not args.quiet:
                print(r['message'])

        if args.verify:
            total = len(results)
            in_sync = sum(1 for r in results if r.get('in_sync', False))
            print(f"\nSummary: {in_sync}/{total} files in sync")
            if out_of_sync > 0:
                print(f"Run without --verify to sync: python convert_schema.py --dir <path>")
                sys.exit(1)

        if errors > 0:
            sys.exit(1)


if __name__ == '__main__':
    main()
