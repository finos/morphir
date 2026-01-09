#!/usr/bin/env python3
"""
validate_tutorial.py - Validate tutorial structure and quality

This script checks tutorials for proper structure, prerequisites,
learning objectives, and code examples.

Usage:
    python validate_tutorial.py <tutorial_path> [--strict] [--suggest]

Options:
    --strict    Fail on any issues
    --suggest   Provide improvement suggestions

Exit codes:
    0 - Tutorial passes validation
    1 - Validation issues found
    2 - Script error
"""

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Dict


@dataclass
class TutorialIssue:
    """Represents a tutorial validation issue."""
    severity: str  # error, warning, suggestion
    category: str
    message: str
    line_number: Optional[int] = None


@dataclass
class TutorialMetrics:
    """Metrics about the tutorial content."""
    word_count: int
    heading_count: int
    code_block_count: int
    image_count: int
    link_count: int
    estimated_reading_time: int  # minutes
    has_prerequisites: bool
    has_objectives: bool
    has_summary: bool
    has_next_steps: bool


# Required sections for a well-structured tutorial
REQUIRED_SECTIONS = [
    'introduction',
    'prerequisites',
    'objectives',
]

RECOMMENDED_SECTIONS = [
    'summary',
    'next steps',
    'conclusion',
]


def extract_frontmatter(content: str) -> tuple[Optional[Dict], str]:
    """Extract YAML frontmatter from content."""
    if not content.startswith('---'):
        return None, content

    match = re.match(r'^---\n(.*?)\n---\n?(.*)$', content, re.DOTALL)
    if not match:
        return None, content

    import yaml
    try:
        frontmatter = yaml.safe_load(match.group(1))
        body = match.group(2)
        return frontmatter, body
    except:
        return None, content


def extract_headings(content: str) -> List[tuple[int, str, int]]:
    """Extract all headings with their level and line number."""
    headings = []
    lines = content.split('\n')
    for i, line in enumerate(lines, 1):
        match = re.match(r'^(#{1,6})\s+(.+)$', line)
        if match:
            level = len(match.group(1))
            title = match.group(2).strip()
            headings.append((level, title, i))
    return headings


def count_code_blocks(content: str) -> int:
    """Count fenced code blocks."""
    return len(re.findall(r'```[\w]*\n', content))


def count_images(content: str) -> int:
    """Count image references."""
    return len(re.findall(r'!\[.*?\]\(.*?\)', content))


def count_links(content: str) -> int:
    """Count markdown links (excluding images)."""
    # Remove images first
    content_no_images = re.sub(r'!\[.*?\]\(.*?\)', '', content)
    return len(re.findall(r'\[.*?\]\(.*?\)', content_no_images))


def estimate_reading_time(word_count: int, code_blocks: int) -> int:
    """Estimate reading time in minutes."""
    # Average reading speed: 200 words per minute
    # Code blocks add ~30 seconds each for understanding
    text_time = word_count / 200
    code_time = code_blocks * 0.5
    return max(1, round(text_time + code_time))


def calculate_metrics(content: str) -> TutorialMetrics:
    """Calculate various metrics about the tutorial."""
    _, body = extract_frontmatter(content)

    # Word count (excluding code blocks)
    text_only = re.sub(r'```.*?```', '', body, flags=re.DOTALL)
    words = len(text_only.split())

    headings = extract_headings(body)
    heading_titles_lower = [h[1].lower() for h in headings]

    code_blocks = count_code_blocks(body)
    images = count_images(body)
    links = count_links(body)

    # Check for key sections
    has_prereq = any('prerequisite' in h or 'requirement' in h for h in heading_titles_lower)
    has_obj = any('objective' in h or 'goal' in h or 'learn' in h for h in heading_titles_lower)
    has_summary = any('summary' in h or 'recap' in h for h in heading_titles_lower)
    has_next = any('next' in h or 'further' in h or 'continue' in h for h in heading_titles_lower)

    return TutorialMetrics(
        word_count=words,
        heading_count=len(headings),
        code_block_count=code_blocks,
        image_count=images,
        link_count=links,
        estimated_reading_time=estimate_reading_time(words, code_blocks),
        has_prerequisites=has_prereq,
        has_objectives=has_obj,
        has_summary=has_summary,
        has_next_steps=has_next
    )


def validate_tutorial(file_path: Path, strict: bool = False) -> tuple[List[TutorialIssue], TutorialMetrics]:
    """Validate a tutorial file."""
    issues = []

    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception as e:
        issues.append(TutorialIssue(
            severity='error',
            category='file',
            message=f"Could not read file: {e}"
        ))
        return issues, None

    frontmatter, body = extract_frontmatter(content)
    metrics = calculate_metrics(content)
    headings = extract_headings(body)

    # Check frontmatter
    if frontmatter is None:
        issues.append(TutorialIssue(
            severity='warning',
            category='frontmatter',
            message="Missing YAML frontmatter"
        ))
    else:
        if 'title' not in frontmatter and 'sidebar_label' not in frontmatter:
            issues.append(TutorialIssue(
                severity='warning',
                category='frontmatter',
                message="No title in frontmatter"
            ))

    # Check for H1 heading
    h1_headings = [h for h in headings if h[0] == 1]
    if len(h1_headings) == 0:
        issues.append(TutorialIssue(
            severity='warning',
            category='structure',
            message="No H1 heading found"
        ))
    elif len(h1_headings) > 1:
        issues.append(TutorialIssue(
            severity='warning',
            category='structure',
            message=f"Multiple H1 headings found ({len(h1_headings)})"
        ))

    # Check heading hierarchy
    prev_level = 0
    for level, title, line in headings:
        if prev_level > 0 and level > prev_level + 1:
            issues.append(TutorialIssue(
                severity='warning',
                category='structure',
                message=f"Heading level skip (H{prev_level} -> H{level})",
                line_number=line
            ))
        prev_level = level

    # Check for required sections
    heading_titles_lower = [h[1].lower() for h in headings]

    if not metrics.has_prerequisites:
        issues.append(TutorialIssue(
            severity='warning' if not strict else 'error',
            category='content',
            message="Missing Prerequisites section"
        ))

    if not metrics.has_objectives:
        issues.append(TutorialIssue(
            severity='suggestion',
            category='content',
            message="Consider adding a Learning Objectives section"
        ))

    # Check for code examples
    if metrics.code_block_count == 0:
        issues.append(TutorialIssue(
            severity='warning',
            category='content',
            message="No code examples found"
        ))
    elif metrics.code_block_count < 2:
        issues.append(TutorialIssue(
            severity='suggestion',
            category='content',
            message="Consider adding more code examples"
        ))

    # Check code block language specifications
    code_blocks_no_lang = len(re.findall(r'```\n', body))
    if code_blocks_no_lang > 0:
        issues.append(TutorialIssue(
            severity='warning',
            category='code',
            message=f"{code_blocks_no_lang} code block(s) without language specification"
        ))

    # Check word count
    if metrics.word_count < 200:
        issues.append(TutorialIssue(
            severity='warning',
            category='content',
            message=f"Tutorial seems very short ({metrics.word_count} words)"
        ))

    # Check for introduction paragraph
    lines = body.split('\n')
    first_paragraph = ""
    in_paragraph = False
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith('#') or stripped.startswith('```'):
            if in_paragraph:
                break
            continue
        in_paragraph = True
        first_paragraph += stripped + " "

    if len(first_paragraph.split()) < 20:
        issues.append(TutorialIssue(
            severity='suggestion',
            category='content',
            message="Consider expanding the introduction paragraph"
        ))

    # Check for summary/conclusion
    if not metrics.has_summary and not metrics.has_next_steps:
        issues.append(TutorialIssue(
            severity='suggestion',
            category='content',
            message="Consider adding a Summary or Next Steps section"
        ))

    return issues, metrics


def format_output(file_path: Path, issues: List[TutorialIssue], metrics: TutorialMetrics,
                  show_suggestions: bool = True) -> str:
    """Format validation output."""
    lines = []
    lines.append(f"Tutorial Validation: {file_path.name}")
    lines.append("=" * 50)
    lines.append("")

    if metrics:
        lines.append("Metrics:")
        lines.append(f"  Word count: {metrics.word_count}")
        lines.append(f"  Reading time: ~{metrics.estimated_reading_time} min")
        lines.append(f"  Headings: {metrics.heading_count}")
        lines.append(f"  Code blocks: {metrics.code_block_count}")
        lines.append(f"  Images: {metrics.image_count}")
        lines.append(f"  Links: {metrics.link_count}")
        lines.append("")

        lines.append("Structure:")
        lines.append(f"  Prerequisites: {'Yes' if metrics.has_prerequisites else 'No'}")
        lines.append(f"  Objectives: {'Yes' if metrics.has_objectives else 'No'}")
        lines.append(f"  Summary: {'Yes' if metrics.has_summary else 'No'}")
        lines.append(f"  Next Steps: {'Yes' if metrics.has_next_steps else 'No'}")
        lines.append("")

    if issues:
        errors = [i for i in issues if i.severity == 'error']
        warnings = [i for i in issues if i.severity == 'warning']
        suggestions = [i for i in issues if i.severity == 'suggestion']

        if errors:
            lines.append("Errors:")
            for issue in errors:
                loc = f" (line {issue.line_number})" if issue.line_number else ""
                lines.append(f"  - [{issue.category}] {issue.message}{loc}")
            lines.append("")

        if warnings:
            lines.append("Warnings:")
            for issue in warnings:
                loc = f" (line {issue.line_number})" if issue.line_number else ""
                lines.append(f"  - [{issue.category}] {issue.message}{loc}")
            lines.append("")

        if suggestions and show_suggestions:
            lines.append("Suggestions:")
            for issue in suggestions:
                lines.append(f"  - {issue.message}")
            lines.append("")
    else:
        lines.append("No issues found!")

    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Validate tutorial structure and quality"
    )
    parser.add_argument('path', help="Path to tutorial file or directory")
    parser.add_argument('--strict', action='store_true',
                        help="Treat warnings as errors")
    parser.add_argument('--suggest', action='store_true',
                        help="Show improvement suggestions")
    parser.add_argument('--quiet', '-q', action='store_true',
                        help="Only show errors")

    args = parser.parse_args()

    target = Path(args.path)
    if not target.exists():
        print(f"Error: Path not found: {target}", file=sys.stderr)
        sys.exit(2)

    # Collect files
    if target.is_file():
        files = [target]
    else:
        files = list(target.rglob('*.md'))

    if not files:
        print("No markdown files found", file=sys.stderr)
        sys.exit(2)

    total_errors = 0
    total_warnings = 0

    for file_path in files:
        issues, metrics = validate_tutorial(file_path, args.strict)

        if not args.quiet or any(i.severity in ('error', 'warning') for i in issues):
            print(format_output(file_path, issues, metrics, args.suggest))
            print("")

        errors = len([i for i in issues if i.severity == 'error'])
        warnings = len([i for i in issues if i.severity == 'warning'])

        total_errors += errors
        if args.strict:
            total_errors += warnings
        else:
            total_warnings += warnings

    # Summary for multiple files
    if len(files) > 1:
        print(f"Summary: {len(files)} files, {total_errors} errors, {total_warnings} warnings")

    if total_errors > 0:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
