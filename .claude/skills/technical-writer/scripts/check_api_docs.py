#!/usr/bin/env python3
"""
check_api_docs.py - Check that public APIs are documented

This script analyzes Go source code to identify public APIs (exported functions,
types, methods) and verifies they have proper documentation comments.

Usage:
    python check_api_docs.py [--path PATH] [--format FORMAT] [--strict]

Options:
    --path PATH     Path to check (default: pkg/)
    --format FORMAT Output format: text, json, markdown (default: text)
    --strict        Fail if any undocumented exports are found

Exit codes:
    0 - All public APIs are documented (or not in strict mode)
    1 - Undocumented public APIs found (in strict mode)
    2 - Script error
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import List, Dict, Optional, Tuple

@dataclass
class PublicAPI:
    """Represents a public API element."""
    file_path: str
    line_number: int
    api_type: str  # function, type, method, const, var
    name: str
    signature: str
    has_doc: bool
    doc_comment: Optional[str] = None
    receiver: Optional[str] = None  # For methods


def is_go_exported(name: str) -> bool:
    """Check if a Go identifier is exported (starts with uppercase)."""
    return bool(name) and name[0].isupper()


def extract_doc_comment(lines: List[str], target_line: int) -> Tuple[bool, Optional[str]]:
    """Extract documentation comment preceding a declaration."""
    doc_lines = []
    i = target_line - 2  # 0-indexed, look at line before

    # Walk backwards collecting comment lines
    while i >= 0:
        line = lines[i].strip()
        if line.startswith('//'):
            doc_lines.insert(0, line[2:].strip())
            i -= 1
        elif line.startswith('/*') or line.endswith('*/'):
            # Block comments - simplified handling
            doc_lines.insert(0, line.strip('/* '))
            i -= 1
        elif not line:
            # Empty line breaks the doc comment chain
            break
        else:
            break

    if doc_lines:
        return True, '\n'.join(doc_lines)
    return False, None


def parse_go_file(file_path: Path) -> List[PublicAPI]:
    """Parse a Go file and extract public API elements."""
    apis = []

    try:
        content = file_path.read_text(encoding='utf-8')
        lines = content.split('\n')
    except Exception:
        return apis

    # Patterns for Go declarations
    func_pattern = re.compile(
        r'^func\s+(?:\((\w+)\s+\*?(\w+)\)\s+)?(\w+)\s*\(([^)]*)\)(?:\s*\(([^)]*)\)|\s*(\w+))?\s*\{'
    )
    type_pattern = re.compile(r'^type\s+(\w+)\s+(struct|interface|[\w\[\]]+)')
    const_pattern = re.compile(r'^const\s+(\w+)\s*=')
    var_pattern = re.compile(r'^var\s+(\w+)\s+')

    for i, line in enumerate(lines, 1):
        stripped = line.strip()

        # Check for function/method
        match = func_pattern.match(stripped)
        if match:
            receiver_name, receiver_type, func_name, params, multi_return, single_return = match.groups()

            if is_go_exported(func_name):
                has_doc, doc = extract_doc_comment(lines, i)

                return_type = multi_return or single_return or ""
                if receiver_type:
                    api_type = "method"
                    signature = f"({receiver_name} *{receiver_type}) {func_name}({params})"
                else:
                    api_type = "function"
                    signature = f"{func_name}({params})"

                if return_type:
                    signature += f" {return_type}"

                apis.append(PublicAPI(
                    file_path=str(file_path),
                    line_number=i,
                    api_type=api_type,
                    name=func_name,
                    signature=signature,
                    has_doc=has_doc,
                    doc_comment=doc,
                    receiver=receiver_type
                ))
            continue

        # Check for type declaration
        match = type_pattern.match(stripped)
        if match:
            type_name, type_kind = match.groups()
            if is_go_exported(type_name):
                has_doc, doc = extract_doc_comment(lines, i)
                apis.append(PublicAPI(
                    file_path=str(file_path),
                    line_number=i,
                    api_type="type",
                    name=type_name,
                    signature=f"type {type_name} {type_kind}",
                    has_doc=has_doc,
                    doc_comment=doc
                ))
            continue

        # Check for const
        match = const_pattern.match(stripped)
        if match:
            const_name = match.group(1)
            if is_go_exported(const_name):
                has_doc, doc = extract_doc_comment(lines, i)
                apis.append(PublicAPI(
                    file_path=str(file_path),
                    line_number=i,
                    api_type="const",
                    name=const_name,
                    signature=f"const {const_name}",
                    has_doc=has_doc,
                    doc_comment=doc
                ))
            continue

        # Check for var
        match = var_pattern.match(stripped)
        if match:
            var_name = match.group(1)
            if is_go_exported(var_name):
                has_doc, doc = extract_doc_comment(lines, i)
                apis.append(PublicAPI(
                    file_path=str(file_path),
                    line_number=i,
                    api_type="var",
                    name=var_name,
                    signature=f"var {var_name}",
                    has_doc=has_doc,
                    doc_comment=doc
                ))

    return apis


def format_text_output(apis: List[PublicAPI], show_all: bool = False) -> str:
    """Format output as text."""
    lines = []

    documented = [a for a in apis if a.has_doc]
    undocumented = [a for a in apis if not a.has_doc]

    lines.append(f"Public API Documentation Report")
    lines.append(f"=" * 40)
    lines.append(f"Total public APIs: {len(apis)}")
    lines.append(f"Documented: {len(documented)} ({100*len(documented)//len(apis) if apis else 0}%)")
    lines.append(f"Undocumented: {len(undocumented)}")
    lines.append("")

    if undocumented:
        lines.append("Undocumented APIs:")
        lines.append("-" * 40)

        # Group by file
        by_file: Dict[str, List[PublicAPI]] = {}
        for api in undocumented:
            if api.file_path not in by_file:
                by_file[api.file_path] = []
            by_file[api.file_path].append(api)

        for file_path, file_apis in sorted(by_file.items()):
            lines.append(f"\n{file_path}:")
            for api in sorted(file_apis, key=lambda x: x.line_number):
                lines.append(f"  L{api.line_number}: {api.api_type} {api.name}")

    return '\n'.join(lines)


def format_markdown_output(apis: List[PublicAPI]) -> str:
    """Format output as markdown for documentation."""
    lines = []

    documented = [a for a in apis if a.has_doc]
    undocumented = [a for a in apis if not a.has_doc]
    coverage = 100 * len(documented) // len(apis) if apis else 100

    lines.append("# API Documentation Coverage Report")
    lines.append("")
    lines.append(f"**Coverage:** {coverage}% ({len(documented)}/{len(apis)} APIs documented)")
    lines.append("")

    if undocumented:
        lines.append("## Undocumented APIs")
        lines.append("")
        lines.append("The following public APIs need documentation:")
        lines.append("")

        # Group by file
        by_file: Dict[str, List[PublicAPI]] = {}
        for api in undocumented:
            if api.file_path not in by_file:
                by_file[api.file_path] = []
            by_file[api.file_path].append(api)

        for file_path, file_apis in sorted(by_file.items()):
            lines.append(f"### `{file_path}`")
            lines.append("")
            for api in sorted(file_apis, key=lambda x: x.line_number):
                lines.append(f"- **{api.api_type}** `{api.name}` (line {api.line_number})")
            lines.append("")

    lines.append("## How to Add Documentation")
    lines.append("")
    lines.append("Add a comment block immediately before the declaration:")
    lines.append("")
    lines.append("```go")
    lines.append("// FunctionName does something important.")
    lines.append("// It takes parameters and returns results.")
    lines.append("func FunctionName(param Type) Result {")
    lines.append("```")

    return '\n'.join(lines)


def format_json_output(apis: List[PublicAPI]) -> str:
    """Format output as JSON."""
    documented = [a for a in apis if a.has_doc]
    undocumented = [a for a in apis if not a.has_doc]

    output = {
        "summary": {
            "total": len(apis),
            "documented": len(documented),
            "undocumented": len(undocumented),
            "coverage_percent": 100 * len(documented) // len(apis) if apis else 100
        },
        "undocumented_apis": [asdict(a) for a in undocumented],
        "documented_apis": [asdict(a) for a in documented]
    }

    return json.dumps(output, indent=2)


def main():
    parser = argparse.ArgumentParser(
        description="Check that public APIs are documented"
    )
    parser.add_argument('--path', default=None,
                        help="Path to check (default: pkg/)")
    parser.add_argument('--format', choices=['text', 'json', 'markdown'],
                        default='text', help="Output format")
    parser.add_argument('--strict', action='store_true',
                        help="Exit with error if undocumented APIs found")
    parser.add_argument('--threshold', type=int, default=0,
                        help="Minimum coverage percentage required (0-100)")

    args = parser.parse_args()

    # Find project root
    script_dir = Path(__file__).parent
    project_root = script_dir.parent.parent.parent.parent.parent

    if args.path:
        target = Path(args.path)
        if not target.is_absolute():
            target = Path.cwd() / target
    else:
        target = project_root / 'pkg'

    if not target.exists():
        print(f"Error: Path not found: {target}", file=sys.stderr)
        sys.exit(2)

    # Collect all Go files
    if target.is_file():
        go_files = [target] if target.suffix == '.go' else []
    else:
        go_files = list(target.rglob('*.go'))
        # Exclude test files
        go_files = [f for f in go_files if not f.name.endswith('_test.go')]

    if not go_files:
        print(f"No Go files found in: {target}", file=sys.stderr)
        sys.exit(2)

    # Parse all files
    all_apis: List[PublicAPI] = []
    for go_file in go_files:
        apis = parse_go_file(go_file)
        all_apis.extend(apis)

    if not all_apis:
        print("No public APIs found")
        sys.exit(0)

    # Format output
    if args.format == 'json':
        print(format_json_output(all_apis))
    elif args.format == 'markdown':
        print(format_markdown_output(all_apis))
    else:
        print(format_text_output(all_apis))

    # Check coverage
    documented = [a for a in all_apis if a.has_doc]
    coverage = 100 * len(documented) // len(all_apis)

    if args.threshold > 0 and coverage < args.threshold:
        print(f"\nError: Coverage {coverage}% is below threshold {args.threshold}%",
              file=sys.stderr)
        sys.exit(1)

    if args.strict and len(documented) < len(all_apis):
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
