#!/usr/bin/env python3
"""
Check for drift between Morphir IR JSON Schema and implementation.

This script helps detect when:
1. YAML and JSON schema files are out of sync
2. Schema definitions don't match Go model implementations (basic structural checks)
3. New types are added to code but not documented in schema

The script performs static analysis and reports potential issues for review.

Usage:
    # Check schema file sync (YAML vs JSON)
    python check_schema_drift.py --sync

    # Check for drift between schema and Go models
    python check_schema_drift.py --code

    # Full drift report
    python check_schema_drift.py --all

    # JSON output for CI integration
    python check_schema_drift.py --all --json

Requirements:
    pip install pyyaml
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# Default paths (relative to repo root)
DEFAULT_SCHEMA_DIR = 'website/static/schemas'
DEFAULT_GO_MODEL_DIR = 'pkg/models/ir'
DEFAULT_GO_SCHEMA_DIR = 'pkg/models/ir/schema'


def find_repo_root() -> Path:
    """Find the repository root by looking for .git directory."""
    current = Path.cwd()
    while current != current.parent:
        if (current / '.git').exists() or (current / 'go.work').exists():
            return current
        current = current.parent
    return Path.cwd()


def check_yaml_json_sync(schema_dir: Path) -> List[dict]:
    """
    Check that YAML and JSON schema files are in sync.

    Returns list of issues found.
    """
    issues = []

    yaml_files = list(schema_dir.glob('*.yaml'))
    json_files = {f.stem: f for f in schema_dir.glob('*.json')}

    for yaml_path in yaml_files:
        json_path = json_files.get(yaml_path.stem)

        if json_path is None:
            issues.append({
                'type': 'missing_json',
                'severity': 'error',
                'file': yaml_path.name,
                'message': f"Missing JSON version of {yaml_path.name}"
            })
            continue

        # Load and compare
        try:
            with open(yaml_path, 'r', encoding='utf-8') as f:
                yaml_schema = yaml.safe_load(f)
            with open(json_path, 'r', encoding='utf-8') as f:
                json_schema = json.load(f)
        except Exception as e:
            issues.append({
                'type': 'parse_error',
                'severity': 'error',
                'file': yaml_path.name,
                'message': f"Failed to parse: {e}"
            })
            continue

        # Normalize $id for comparison
        yaml_normalized = dict(yaml_schema)
        if '$id' in yaml_normalized and yaml_normalized['$id'].endswith('.yaml'):
            yaml_normalized['$id'] = yaml_normalized['$id'].replace('.yaml', '.json')

        if yaml_normalized != json_schema:
            issues.append({
                'type': 'content_mismatch',
                'severity': 'error',
                'file': yaml_path.name,
                'message': f"{yaml_path.name} and {json_path.name} are out of sync",
                'fix': f"Run: python convert_schema.py {yaml_path}"
            })

    # Check for orphan JSON files
    yaml_stems = {f.stem for f in yaml_files}
    for json_stem, json_path in json_files.items():
        if json_stem not in yaml_stems:
            issues.append({
                'type': 'orphan_json',
                'severity': 'warning',
                'file': json_path.name,
                'message': f"JSON file {json_path.name} has no corresponding YAML source"
            })

    return issues


def extract_schema_types(schema_path: Path) -> Set[str]:
    """Extract type names defined in a JSON schema file."""
    types = set()

    try:
        with open(schema_path, 'r', encoding='utf-8') as f:
            if schema_path.suffix == '.yaml':
                schema = yaml.safe_load(f)
            else:
                schema = json.load(f)
    except Exception:
        return types

    # Extract from definitions
    definitions = schema.get('definitions', {})
    types.update(definitions.keys())

    return types


def extract_go_types(go_dir: Path) -> Dict[str, dict]:
    """
    Extract type definitions from Go source files.

    Returns dict mapping type names to their info.
    """
    types = {}

    if not go_dir.exists():
        return types

    # Pattern to match Go type definitions
    type_pattern = re.compile(
        r'type\s+([A-Z][a-zA-Z0-9]*)\s+(?:struct|interface|\[\]|map\[|[a-z])',
        re.MULTILINE
    )

    # Pattern to match const blocks with type definitions (for enums)
    const_pattern = re.compile(
        r'const\s*\(\s*([^)]+)\)',
        re.MULTILINE | re.DOTALL
    )

    for go_file in go_dir.rglob('*.go'):
        if '_test.go' in go_file.name:
            continue

        try:
            content = go_file.read_text(encoding='utf-8')
        except Exception:
            continue

        # Find type definitions
        for match in type_pattern.finditer(content):
            type_name = match.group(1)
            types[type_name] = {
                'file': str(go_file.relative_to(go_dir)),
                'line': content[:match.start()].count('\n') + 1,
                'kind': 'type'
            }

    return types


def check_schema_code_drift(schema_dir: Path, go_model_dir: Path) -> List[dict]:
    """
    Check for drift between schema definitions and Go code.

    This performs basic structural analysis to identify potential issues.
    """
    issues = []

    # Get the latest schema (v3)
    v3_schema = schema_dir / 'morphir-ir-v3.yaml'
    if not v3_schema.exists():
        issues.append({
            'type': 'missing_schema',
            'severity': 'error',
            'file': 'morphir-ir-v3.yaml',
            'message': "Cannot find v3 schema file"
        })
        return issues

    schema_types = extract_schema_types(v3_schema)
    go_types = extract_go_types(go_model_dir)

    # Known mappings between schema and Go types
    # Schema types often use different naming conventions
    type_mappings = {
        'Name': ['Name', 'IRName'],
        'FQName': ['FQName', 'FullyQualifiedName'],
        'PackageName': ['PackageName', 'PackagePath'],
        'ModuleName': ['ModuleName', 'ModulePath'],
        'Type': ['Type', 'IRType'],
        'Value': ['Value', 'IRValue'],
        'Pattern': ['Pattern', 'IRPattern'],
        'Literal': ['Literal', 'IRLiteral'],
        'Definition': ['Definition', 'TypeDefinition', 'ValueDefinition'],
        'AccessControlled': ['AccessControlled', 'Accessibility'],
    }

    # Check for schema types that might not have Go implementations
    for schema_type in sorted(schema_types):
        # Skip internal schema constructs
        if schema_type.startswith('_') or schema_type in ['definitions']:
            continue

        # Check if we have a matching Go type
        possible_go_names = type_mappings.get(schema_type, [schema_type])
        found = False
        for go_name in possible_go_names:
            if go_name in go_types:
                found = True
                break

        if not found:
            # This might be a composite type or embedded in another struct
            # Flag as info, not error
            issues.append({
                'type': 'potential_missing_impl',
                'severity': 'info',
                'schema_type': schema_type,
                'message': f"Schema type '{schema_type}' may not have a direct Go implementation",
                'note': "This might be intentional (embedded in another type or represented differently)"
            })

    # Check for Go types that might need schema documentation
    # Focus on exported types in the IR model package
    ir_related_patterns = ['IR', 'Morphir', 'Type', 'Value', 'Name', 'Module', 'Package']

    for go_type, info in sorted(go_types.items()):
        # Check if this looks like an IR-related type
        is_ir_related = any(pattern in go_type for pattern in ir_related_patterns)

        if is_ir_related and go_type not in schema_types:
            # Check mappings
            found_in_schema = False
            for schema_type, go_names in type_mappings.items():
                if go_type in go_names and schema_type in schema_types:
                    found_in_schema = True
                    break

            if not found_in_schema:
                issues.append({
                    'type': 'undocumented_type',
                    'severity': 'info',
                    'go_type': go_type,
                    'file': info['file'],
                    'message': f"Go type '{go_type}' may not be documented in schema",
                    'note': "Review if this type should be added to the schema"
                })

    return issues


def generate_report(issues: List[dict], format: str = 'text') -> str:
    """Generate a formatted report of issues found."""
    if format == 'json':
        return json.dumps({
            'issues': issues,
            'summary': {
                'total': len(issues),
                'errors': sum(1 for i in issues if i.get('severity') == 'error'),
                'warnings': sum(1 for i in issues if i.get('severity') == 'warning'),
                'info': sum(1 for i in issues if i.get('severity') == 'info')
            }
        }, indent=2)

    if not issues:
        return "No drift detected."

    lines = ["Schema Drift Report", "=" * 50, ""]

    # Group by severity
    for severity in ['error', 'warning', 'info']:
        severity_issues = [i for i in issues if i.get('severity') == severity]
        if severity_issues:
            lines.append(f"\n{severity.upper()}S ({len(severity_issues)}):")
            lines.append("-" * 30)
            for issue in severity_issues:
                lines.append(f"  [{issue['type']}] {issue['message']}")
                if 'fix' in issue:
                    lines.append(f"    Fix: {issue['fix']}")
                if 'note' in issue:
                    lines.append(f"    Note: {issue['note']}")

    lines.append("")
    lines.append(f"Total: {len(issues)} issues "
                 f"({sum(1 for i in issues if i.get('severity') == 'error')} errors, "
                 f"{sum(1 for i in issues if i.get('severity') == 'warning')} warnings, "
                 f"{sum(1 for i in issues if i.get('severity') == 'info')} info)")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Check for drift between Morphir IR schemas and implementation',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('--sync', '-s', action='store_true',
                        help='Check YAML/JSON schema file sync only')
    parser.add_argument('--code', '-c', action='store_true',
                        help='Check schema vs Go code drift only')
    parser.add_argument('--all', '-a', action='store_true',
                        help='Run all drift checks')
    parser.add_argument('--schema-dir', metavar='DIR',
                        help=f'Schema directory (default: {DEFAULT_SCHEMA_DIR})')
    parser.add_argument('--go-dir', metavar='DIR',
                        help=f'Go model directory (default: {DEFAULT_GO_MODEL_DIR})')
    parser.add_argument('--json', action='store_true',
                        help='Output in JSON format')
    parser.add_argument('--strict', action='store_true',
                        help='Exit with error code on any issues (including info)')

    args = parser.parse_args()

    # Default to --all if no specific check is requested
    if not (args.sync or args.code or args.all):
        args.all = True

    repo_root = find_repo_root()
    schema_dir = Path(args.schema_dir) if args.schema_dir else repo_root / DEFAULT_SCHEMA_DIR
    go_dir = Path(args.go_dir) if args.go_dir else repo_root / DEFAULT_GO_MODEL_DIR

    all_issues = []

    # Run requested checks
    if args.sync or args.all:
        if schema_dir.exists():
            sync_issues = check_yaml_json_sync(schema_dir)
            all_issues.extend(sync_issues)
        else:
            all_issues.append({
                'type': 'missing_dir',
                'severity': 'warning',
                'message': f"Schema directory not found: {schema_dir}"
            })

    if args.code or args.all:
        if schema_dir.exists() and go_dir.exists():
            code_issues = check_schema_code_drift(schema_dir, go_dir)
            all_issues.extend(code_issues)
        elif not go_dir.exists():
            all_issues.append({
                'type': 'missing_dir',
                'severity': 'info',
                'message': f"Go model directory not found: {go_dir} (may be in different repo)"
            })

    # Output report
    report = generate_report(all_issues, 'json' if args.json else 'text')
    print(report)

    # Exit code
    errors = sum(1 for i in all_issues if i.get('severity') == 'error')
    if errors > 0:
        sys.exit(1)
    elif args.strict and all_issues:
        sys.exit(1)


if __name__ == '__main__':
    main()
