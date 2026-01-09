#!/usr/bin/env python3
"""
Generate llms.txt files for Morphir documentation.

This script creates LLM-friendly documentation files following the llms.txt
specification (https://llmstxt.org/). It generates both compact and full
versions:

- llms.txt: Compact version with curated links and descriptions
- llms-full.txt: Full version with inline content from key documents

Usage:
    # Generate both versions
    python generate_llms_txt.py

    # Generate only compact version
    python generate_llms_txt.py --compact-only

    # Generate only full version
    python generate_llms_txt.py --full-only

    # Custom output directory
    python generate_llms_txt.py --output website/static/

    # Preview without writing files
    python generate_llms_txt.py --dry-run
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Try to import yaml for frontmatter parsing
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False


# Base URL for the Morphir documentation site
BASE_URL = "https://morphir.finos.org"

# Documentation sections with their priorities and descriptions
# Priority 1 = most important, included in compact version
# Priority 2 = important, included in compact version
# Priority 3 = optional, only in full version
DOC_SECTIONS = {
    "getting-started": {
        "title": "Getting Started",
        "description": "Installation and first steps with Morphir",
        "priority": 1,
    },
    "concepts": {
        "title": "Core Concepts",
        "description": "Fundamental concepts and theory behind Morphir",
        "priority": 1,
    },
    "user-guides": {
        "title": "User Guides",
        "description": "Practical guides for using Morphir",
        "priority": 2,
    },
    "cli-preview": {
        "title": "CLI Preview",
        "description": "Next-generation command-line interface documentation",
        "priority": 2,
    },
    "spec": {
        "title": "Specifications",
        "description": "Technical specifications including IR format and schemas",
        "priority": 2,
    },
    "reference": {
        "title": "Reference",
        "description": "API reference and backend documentation",
        "priority": 2,
    },
    "developers": {
        "title": "Developer Guide",
        "description": "Contributing to Morphir development",
        "priority": 3,
    },
    "adr": {
        "title": "Architecture Decisions",
        "description": "Architecture Decision Records (ADRs)",
        "priority": 3,
    },
    "community": {
        "title": "Community",
        "description": "Community resources and guidelines",
        "priority": 3,
    },
    "use-cases": {
        "title": "Use Cases",
        "description": "Real-world examples and applications",
        "priority": 3,
    },
}

# Key documents to include with full content in llms-full.txt
KEY_DOCUMENTS = [
    "docs/README.md",
    "docs/morphir-ir-specification.md",
    "docs/getting-started/README.md",
    "docs/concepts/README.md",
    "docs/spec/schemas/index.md",
]


def find_repo_root() -> Path:
    """Find the repository root by looking for .git or website directory."""
    current = Path.cwd()
    while current != current.parent:
        if (current / '.git').exists() or (current / 'website').exists():
            return current
        current = current.parent
    return Path.cwd()


def extract_frontmatter(content: str) -> Tuple[Dict, str]:
    """Extract YAML frontmatter from markdown content."""
    if not content.startswith('---'):
        return {}, content

    # Find the closing ---
    end_match = re.search(r'\n---\s*\n', content[3:])
    if not end_match:
        return {}, content

    frontmatter_text = content[3:end_match.start() + 3]
    body = content[end_match.end() + 3:]

    if HAS_YAML:
        try:
            frontmatter = yaml.safe_load(frontmatter_text)
            return frontmatter or {}, body
        except yaml.YAMLError:
            return {}, content
    else:
        # Basic parsing without yaml
        frontmatter = {}
        for line in frontmatter_text.split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                frontmatter[key.strip()] = value.strip().strip('"\'')
        return frontmatter, body


def extract_title(content: str, frontmatter: Dict) -> str:
    """Extract title from frontmatter or first H1 heading."""
    if 'title' in frontmatter:
        return frontmatter['title']

    # Look for first H1
    match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
    if match:
        return match.group(1).strip()

    return "Untitled"


def extract_description(content: str, frontmatter: Dict, max_length: int = 200) -> str:
    """Extract description from frontmatter or first paragraph."""
    if 'description' in frontmatter:
        return frontmatter['description']

    # Remove frontmatter and find first paragraph
    _, body = extract_frontmatter(content)

    # Skip headings and find first paragraph
    lines = body.strip().split('\n')
    paragraph_lines = []
    in_paragraph = False

    for line in lines:
        line = line.strip()
        if not line:
            if in_paragraph:
                break
            continue
        if line.startswith('#') or line.startswith('```') or line.startswith('|'):
            if in_paragraph:
                break
            continue
        in_paragraph = True
        paragraph_lines.append(line)

    description = ' '.join(paragraph_lines)
    if len(description) > max_length:
        description = description[:max_length-3] + "..."

    return description


def clean_content_for_llm(content: str) -> str:
    """Clean markdown content for LLM consumption."""
    # Remove frontmatter
    _, body = extract_frontmatter(content)

    # Remove HTML comments
    body = re.sub(r'<!--.*?-->', '', body, flags=re.DOTALL)

    # Remove import statements (MDX)
    body = re.sub(r'^import\s+.*$', '', body, flags=re.MULTILINE)

    # Remove excessive blank lines
    body = re.sub(r'\n{3,}', '\n\n', body)

    return body.strip()


def scan_docs(docs_dir: Path) -> Dict[str, List[Dict]]:
    """Scan documentation directory and organize by section."""
    sections = {}

    for section_name, section_info in DOC_SECTIONS.items():
        section_path = docs_dir / section_name
        if not section_path.exists():
            continue

        docs = []
        for md_file in sorted(section_path.rglob('*.md')):
            # Skip files in hidden directories
            if any(part.startswith('.') for part in md_file.parts):
                continue

            try:
                content = md_file.read_text(encoding='utf-8')
            except Exception:
                continue

            frontmatter, _ = extract_frontmatter(content)
            title = extract_title(content, frontmatter)
            description = extract_description(content, frontmatter)

            # Build URL path
            rel_path = md_file.relative_to(docs_dir)
            url_path = str(rel_path).replace('.md', '').replace('/README', '')
            if url_path.endswith('/index'):
                url_path = url_path[:-6]

            docs.append({
                'title': title,
                'description': description,
                'url': f"{BASE_URL}/docs/{url_path}/",
                'path': str(rel_path),
                'priority': section_info['priority'],
            })

        if docs:
            sections[section_name] = {
                'info': section_info,
                'docs': docs,
            }

    return sections


def generate_compact(sections: Dict[str, List[Dict]], docs_dir: Path) -> str:
    """Generate compact llms.txt content."""
    lines = []

    # H1 - Project name
    lines.append("# Morphir")
    lines.append("")

    # Blockquote - Brief summary
    lines.append("> Morphir is a library of tools that works to capture business logic")
    lines.append("> as data in a language-agnostic intermediate representation (IR).")
    lines.append("> It provides a type-safe, functional approach to defining and")
    lines.append("> transforming business rules across multiple platforms.")
    lines.append("")

    # Key information
    lines.append("Morphir enables you to write business logic once and deploy it to")
    lines.append("multiple targets including Scala, TypeScript, Spark, and more.")
    lines.append("The IR preserves full semantic information making it suitable for")
    lines.append("analysis, optimization, and cross-platform code generation.")
    lines.append("")

    # Core documentation section
    lines.append("## Docs")
    lines.append("")

    # Add priority 1 and 2 sections
    for section_name, section_data in sorted(sections.items(),
                                              key=lambda x: x[1]['info']['priority']):
        info = section_data['info']
        if info['priority'] > 2:
            continue

        for doc in section_data['docs'][:5]:  # Limit docs per section
            lines.append(f"- [{doc['title']}]({doc['url']}): {doc['description']}")

    lines.append("")

    # Specifications section
    lines.append("## Specifications")
    lines.append("")
    lines.append(f"- [Morphir IR Specification]({BASE_URL}/docs/morphir-ir-specification/): Complete specification of the Morphir Intermediate Representation format")
    lines.append(f"- [JSON Schemas]({BASE_URL}/docs/spec/schemas/): JSON Schema definitions for validating Morphir IR files")
    lines.append(f"- [Schema v3 (YAML)]({BASE_URL}/schemas/morphir-ir-v3.yaml): Current IR schema in YAML format")
    lines.append(f"- [Schema v3 (JSON)]({BASE_URL}/schemas/morphir-ir-v3.json): Current IR schema in JSON format")
    lines.append("")

    # Optional section
    lines.append("## Optional")
    lines.append("")

    for section_name, section_data in sorted(sections.items(),
                                              key=lambda x: x[1]['info']['priority']):
        info = section_data['info']
        if info['priority'] <= 2:
            continue

        for doc in section_data['docs'][:3]:  # Fewer docs for optional
            lines.append(f"- [{doc['title']}]({doc['url']}): {doc['description']}")

    return '\n'.join(lines)


def generate_full(sections: Dict[str, List[Dict]], docs_dir: Path) -> str:
    """Generate full llms-full.txt content with inline documentation."""
    lines = []

    # H1 - Project name
    lines.append("# Morphir - Complete Documentation")
    lines.append("")

    # Blockquote - Brief summary
    lines.append("> Morphir is a library of tools that works to capture business logic")
    lines.append("> as data in a language-agnostic intermediate representation (IR).")
    lines.append("> This file contains the complete inline documentation for LLM consumption.")
    lines.append("")

    # Include key documents inline
    lines.append("## Core Documentation")
    lines.append("")

    for doc_path in KEY_DOCUMENTS:
        full_path = docs_dir.parent / doc_path
        if not full_path.exists():
            # Try relative to docs_dir
            full_path = docs_dir / doc_path.replace('docs/', '')

        if full_path.exists():
            try:
                content = full_path.read_text(encoding='utf-8')
                frontmatter, _ = extract_frontmatter(content)
                title = extract_title(content, frontmatter)
                cleaned = clean_content_for_llm(content)

                lines.append(f"### {title}")
                lines.append("")
                lines.append(cleaned)
                lines.append("")
                lines.append("---")
                lines.append("")
            except Exception as e:
                lines.append(f"<!-- Failed to load {doc_path}: {e} -->")
                lines.append("")

    # Section summaries with links
    lines.append("## Documentation Index")
    lines.append("")

    for section_name, section_data in sorted(sections.items(),
                                              key=lambda x: x[1]['info']['priority']):
        info = section_data['info']
        lines.append(f"### {info['title']}")
        lines.append("")
        lines.append(f"{info['description']}")
        lines.append("")

        for doc in section_data['docs']:
            lines.append(f"- [{doc['title']}]({doc['url']}): {doc['description']}")

        lines.append("")

    # Specifications
    lines.append("## JSON Schema Specifications")
    lines.append("")
    lines.append("Morphir IR files can be validated against these JSON Schemas:")
    lines.append("")
    lines.append(f"- Version 3 (Current): [{BASE_URL}/schemas/morphir-ir-v3.yaml]({BASE_URL}/schemas/morphir-ir-v3.yaml)")
    lines.append(f"- Version 2: [{BASE_URL}/schemas/morphir-ir-v2.yaml]({BASE_URL}/schemas/morphir-ir-v2.yaml)")
    lines.append(f"- Version 1: [{BASE_URL}/schemas/morphir-ir-v1.yaml]({BASE_URL}/schemas/morphir-ir-v1.yaml)")
    lines.append("")
    lines.append("JSON format schemas are also available by replacing `.yaml` with `.json`.")
    lines.append("")

    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Generate llms.txt files for Morphir documentation',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('--output', '-o', metavar='DIR',
                        help='Output directory (default: website/static/)')
    parser.add_argument('--docs', '-d', metavar='DIR',
                        help='Documentation directory (default: docs/)')
    parser.add_argument('--compact-only', action='store_true',
                        help='Generate only compact llms.txt')
    parser.add_argument('--full-only', action='store_true',
                        help='Generate only full llms-full.txt')
    parser.add_argument('--dry-run', action='store_true',
                        help='Preview output without writing files')
    parser.add_argument('--stdout', action='store_true',
                        help='Write to stdout instead of files')

    args = parser.parse_args()

    repo_root = find_repo_root()
    docs_dir = Path(args.docs) if args.docs else repo_root / 'docs'
    output_dir = Path(args.output) if args.output else repo_root / 'website' / 'static'

    if not docs_dir.exists():
        print(f"Error: Documentation directory not found: {docs_dir}", file=sys.stderr)
        sys.exit(1)

    # Scan documentation
    print(f"Scanning documentation in {docs_dir}...", file=sys.stderr)
    sections = scan_docs(docs_dir)

    total_docs = sum(len(s['docs']) for s in sections.values())
    print(f"Found {total_docs} documents in {len(sections)} sections", file=sys.stderr)

    # Generate content
    if not args.full_only:
        compact_content = generate_compact(sections, docs_dir)

        if args.stdout or args.dry_run:
            print("=" * 60)
            print("llms.txt (compact)")
            print("=" * 60)
            print(compact_content)
            print()
        else:
            output_path = output_dir / 'llms.txt'
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(compact_content, encoding='utf-8')
            print(f"Written: {output_path}", file=sys.stderr)

    if not args.compact_only:
        full_content = generate_full(sections, docs_dir)

        if args.stdout or args.dry_run:
            print("=" * 60)
            print("llms-full.txt")
            print("=" * 60)
            print(full_content)
        else:
            output_path = output_dir / 'llms-full.txt'
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(full_content, encoding='utf-8')
            print(f"Written: {output_path}", file=sys.stderr)

    if not args.dry_run and not args.stdout:
        print(f"\nllms.txt files generated in {output_dir}", file=sys.stderr)
        print(f"Access at:", file=sys.stderr)
        print(f"  {BASE_URL}/llms.txt", file=sys.stderr)
        print(f"  {BASE_URL}/llms-full.txt", file=sys.stderr)


if __name__ == '__main__':
    main()
