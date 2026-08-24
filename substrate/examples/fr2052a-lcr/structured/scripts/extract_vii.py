"""
Extractor for Appendix VII (STWF to FR 2052a Mapping).

Pages 180-194 of the PDF (1-indexed). No broken font issues; all content
extracts cleanly via pdfplumber.extract_text().

Structure per page:
  - Intro page (180): title, paragraph, Key table, schedule heading, first item
  - Content pages (181-194): numbered sub-tables (N) and Item headings, ending
    with a bare internal page number

Usage:
    python structured/scripts/extract_vii.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pdfplumber

PDF = Path(__file__).resolve().parents[2] / "raw" / "FR_2052a20250226_f.pdf"
OUT = Path(__file__).resolve().parents[1] / "output" / "04-appendices" / "VII-stwf-mapping.md"

# Page range (1-indexed)
VII_PAGES = range(180, 195)   # pages 180-194

# Known FR 2052a / STWF field names (left column of mapping tables)
KNOWN_FIELDS = {
    "Reporting Entity", "PID", "Product", "Sub-Product", "Sub‐Product",
    "Sub‐product", "Sub-product",
    "Counterparty", "CID", "G-SIB", "G‐SIB",
    "Maturity Amount", "Maturity Bucket", "Maturity Optionality",
    "Effective Maturity Bucket",
    "Forward Start Amount", "Forward Start Bucket",
    "Collateral Class", "Collateral Value", "Collateral Currency",
    "Treasury Control", "Encumbrance Type", "Unencumbered",
    "Accounting Designation",
    "Market Value", "Lendable Value",
    "Internal", "Internal Counterparty",
    "Risk Weight", "Business Line", "Settlement",
    "Rehypothecated", "Loss Absorbency", "Insured", "Trigger",
    "Currency", "Converted",
}


_SORTED_FIELDS = sorted(KNOWN_FIELDS, key=len, reverse=True)


def split_field_value(line: str) -> tuple[str, str] | None:
    """Split a line into (field_name, value). Returns None if not a field row."""
    # Check longest field names first to avoid "Internal" shadowing "Internal Counterparty"
    for field in _SORTED_FIELDS:
        if line == field:
            return (field, "")
        if line.startswith(field + " "):
            rest = line[len(field):].strip()
            return (field, rest)
    # Heuristic: last token is a sentinel and left side looks like a field name
    # (no commas — rules out continuation lines like "Non‐Regulated Fund, or NULL")
    parts = line.rsplit(None, 1)
    if len(parts) == 2 and parts[1] in ("*", "#", "NULL", "Y", "N"):
        candidate = parts[0]
        if "," not in candidate:
            return (candidate, parts[1])
    return None


def format_tables(lines: list[str]) -> str:
    """Convert a flat list of extracted lines into structured markdown."""
    output: list[str] = []
    in_table = False

    i = 0
    while i < len(lines):
        line = lines[i].strip()
        i += 1

        if not line:
            if not in_table:
                output.append("")
            continue

        # -- Table header: "(N) ... PIDs for item N.x" or "(N) ... for item N.x"
        table_header = re.match(r"^\((\d+)\)\s+(.+)$", line)
        if table_header:
            num = table_header.group(1)
            title = table_header.group(2)
            in_table = False
            output.append("")
            output.append(f"### ({num}) {title}")
            continue

        # -- "Field Value" header line → start markdown table
        if line == "Field Value":
            output.append("")
            output.append("| Field | Value |")
            output.append("|-------|-------|")
            in_table = True
            continue

        # -- Item section headings: "Item N.x: ..." or "Item N: ..."
        item_match = re.match(r"^(Item\s+\d+(?:\.[a-z][^:]*)?:.+)$", line)
        if item_match:
            in_table = False
            output.append("")
            output.append(f"## {line}")
            continue

        # -- "FR 2052a to FR Y-15, Schedule G Map" heading
        if line.startswith("FR 2052a to FR Y"):
            in_table = False
            output.append("")
            output.append(f"## {line}")
            continue

        # -- Field/value row
        if in_table:
            fv = split_field_value(line)
            if fv:
                field, value = fv
                field = field.replace("|", "\\|")
                value = value.replace("|", "\\|")
                output.append(f"| {field} | {value} |")
            else:
                # Continuation: append to last table row's value
                escaped = line.replace("|", "\\|")
                joined = False
                for j in range(len(output) - 1, max(len(output) - 5, -1), -1):
                    if output[j].startswith("| ") and output[j].endswith(" |"):
                        output[j] = output[j][:-2] + "<br>" + escaped + " |"
                        joined = True
                        break
                    elif output[j] == "":
                        continue
                    else:
                        break
                if not joined:
                    output.append(line)
            continue

        # Anything else (not in table): emit as prose
        output.append(line)

    return "\n".join(output)


def build_intro(page_text: str) -> tuple[str, list[str]]:
    """
    Parse the intro page (page 180) to extract the header, intro paragraph,
    Key section, and schedule heading. Returns (intro_md, remaining_lines).
    """
    lines = page_text.split("\n")

    intro_parts = []
    remaining = []
    state = "before_key"
    key_rows = []

    idx = 0
    while idx < len(lines):
        line = lines[idx].strip()
        idx += 1

        if not line:
            continue

        if line == "APPENDIX VII: Short-Term Wholesale Funding (STWF) to FR 2052a Mapping":
            # Title is the H1 (used in the file heading)
            continue

        if state == "before_key":
            if line == "Key":
                state = "in_key"
                continue
            intro_parts.append(line)
            continue

        if state == "in_key":
            if line.startswith("FR 2052a to FR Y"):
                state = "after_key"
                remaining.append(line)
                continue
            # Parse key rows: "* Values relevant ..." / "# Values ..." / "NULL ..."
            if line.startswith("*"):
                key_rows.append(("\\*", line[1:].strip()))
            elif line.startswith("#"):
                key_rows.append(("#", line[1:].strip()))
            elif line.startswith("NULL"):
                key_rows.append(("NULL", line[4:].strip()))
            continue

        if state == "after_key":
            remaining.append(line)

    # Build intro markdown
    parts = []
    # Paragraph (join wrapped lines)
    para = " ".join(intro_parts)
    parts.append(para)
    parts.append("")
    # Key table
    parts.append("## Key")
    parts.append("")
    parts.append("| Symbol | Meaning |")
    parts.append("|--------|---------|")
    for sym, meaning in key_rows:
        parts.append(f"| `{sym}` | {meaning} |")
    parts.append("")

    return "\n".join(parts), remaining


def main():
    if sys.stdout.encoding != "utf-8":
        sys.stdout.reconfigure(encoding="utf-8")

    pdf = pdfplumber.open(str(PDF))

    # Collect all lines from VII pages, stripping trailing internal page numbers
    all_lines: list[str] = []
    for pg_num in VII_PAGES:
        page = pdf.pages[pg_num - 1]
        text = (page.extract_text() or "").strip()
        if not text:
            continue
        page_lines = text.split("\n")
        # Strip trailing bare page number
        if page_lines and re.match(r"^\d+$", page_lines[-1].strip()):
            page_lines = page_lines[:-1]
        all_lines.extend(page_lines)
        all_lines.append("")  # blank between pages

    pdf.close()

    # Parse intro from first page separately
    intro_page_text = "\n".join(all_lines)
    intro_end = next(
        (i for i, l in enumerate(all_lines) if l.strip().startswith("FR 2052a to FR Y")),
        0,
    )
    intro_raw = "\n".join(all_lines[:intro_end])
    rest_lines = all_lines[intro_end:]

    intro_md, schedule_header_lines = build_intro(intro_raw + "\n" + all_lines[intro_end])
    rest_lines = all_lines[intro_end + 1:]

    body_md = format_tables(schedule_header_lines + rest_lines)

    # Assemble output
    header = """\
# Appendix VII: Short-Term Wholesale Funding (STWF) to FR 2052a Mapping

> **Hand-curated.** Extracted via `pdfplumber.extract_text()` (pages 180–194).
> No font issues; tables extract cleanly. See
> [`human-annotations.md`](../../human-annotations.md) for layout notes.

"""

    out_text = header + intro_md + "\n" + body_md + "\n"

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(out_text, encoding="utf-8")
    print(f"Wrote {OUT}")
    char_count = len(out_text)
    line_count = out_text.count("\n")
    print(f"  {line_count} lines, {char_count} chars")


if __name__ == "__main__":
    main()
