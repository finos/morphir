"""
Extractor for Appendix VI (LCR to FR 2052a Mapping).

Pages 108-179 of the PDF. The formulas on pages 108-109 use a broken
ToUnicode CMap (Cambria/CambriaMath font subsets that map multiple glyphs
to the same doubled math-italic codepoint), so formula text is
irrecoverable via text extraction. We transcribe those from the LCR Rule
(12 CFR 249) and the visible structure of the garbled output.

Pages 110-179 contain:
  - Page 110: (page number only — blank separator)
  - Page 111: Outflow Adjustment Percentage table
  - Pages 112-179: Numbered field/value mapping provisions

The mapping provisions extract cleanly via pdfplumber.extract_text().

Usage:
    python structured/scripts/extract_vi.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pdfplumber

PDF = Path(__file__).resolve().parents[2] / "raw" / "FR_2052a20250226_f.pdf"
OUT = Path(__file__).resolve().parents[1] / "output" / "04-appendices" / "VI-lcr-mapping.md"

# Page ranges (1-indexed)
FORMULA_PAGES = range(108, 110)    # pages 108-109
TABLE_PAGES = range(111, 180)      # pages 111-179


def build_formula_section() -> str:
    """Hand-transcribed from 12 CFR 249.30 and the mapping document structure."""
    return """\
## LCR Calculation

```
LCR = HQLA adjusted / Total Net Cash Outflows

HQLA adjusted = (Level 1 HQLA adjusted values - Level 1 HQLA haircut values)
    + .85 * (Level 2A HQLA adjusted values - Level 2A HQLA haircut values)
    + .5 * (Level 2B HQLA adjusted values - Level 2B HQLA haircut values)
    - MAX[ Unadjusted excess HQLA, Adjusted excess HQLA ]

Unadjusted excess HQLA = Level 2 cap excess amount + Level 2B cap excess amount

Level 2 cap excess amount = MAX[ 0,
    .85 * (Level 2A HQLA adjusted values - Level 2A HQLA haircut values)
    + .5 * (Level 2B HQLA adjusted values - Level 2B HQLA haircut values)
    - .6667 * (Level 1 HQLA adjusted values - Level 1 HQLA haircut values) ]

Level 2B cap excess amount = MAX[ 0,
    .5 * (Level 2B HQLA adjusted values - Level 2B HQLA haircut values)
    - Level 2 cap excess amount
    - .1765 * ( (Level 1 HQLA adjusted values - Level 1 HQLA haircut values)
        + .85 * (Level 2A HQLA adjusted values - Level 2A HQLA haircut values) ) ]

Adjusted level 1 HQLA adjusted values
    = Level 1 HQLA adjusted values + Secured lending unwind maturity amount
    - Secured lending unwind collateral value with Level 1 collateral class
    - Secured funding unwind maturity amount

Adjusted level 2A HQLA adjusted values
    = Level 2A HQLA adjusted values
    - Secured lending unwind collateral value with Level 2A collateral class
    + Secured funding unwind collateral value with Level 2A collateral class
    + Asset exchange unwind maturity amount with Level 2A security
    - Asset exchange unwind collateral value with Level 2A collateral class

Adjusted level 2B HQLA adjusted values
    = Level 2B HQLA adjusted values
    - Secured lending unwind collateral value with Level 2B collateral class
    + Secured funding unwind collateral value with Level 2B collateral class
    + Asset exchange unwind maturity amount with Level 2B security
    - Asset exchange unwind collateral value with Level 2B collateral class

Adjusted excess HQLA = Adjusted level 2 cap excess amount +
    Adjusted level 2B cap excess amount

Adjusted level 2 cap excess amount = MAX[ 0,
    .85 * (Adjusted level 2A HQLA adjusted values
        - Level 2A HQLA haircut values)
    + .5 * (Adjusted level 2B HQLA adjusted values
        - Level 2B HQLA haircut values)
    - .6667 * (Adjusted level 1 HQLA adjusted values
        - Level 1 HQLA haircut values) ]

Adjusted level 2B cap excess amount = MAX[ 0,
    .5 * (Adjusted level 2B HQLA adjusted values
        - Level 2B HQLA haircut values)
    - Adjusted level 2 cap excess amount
    - .1765 * ( (Adjusted level 1 HQLA adjusted values
        - Level 1 HQLA haircut values)
        + .85 * (Adjusted level 2A HQLA adjusted values
            - Level 2A HQLA haircut values) ) ]

Total Net Cash Outflows
    = Outflow Adjustment Percentage * [ Outflow values
        * Runoff or rate
        - MIN [ Inflow values
            * Runoff inflow rate, .75 * (Outflow values * Runoff or rate) ]
        + Maturity mismatch add on ]

Maturity mismatch add on
    = MAX [ 0, Largest net cumulative maturity outflow amount ]
    - MAX [ 0, Net day 30 cumulative maturity outflow amount ]
```

[^1]: Refer to LCR Rule as defined as specified in section 10(c) of the LRM standards.
[^2]: For the maturity mismatch add-on, please note that Open maturity should still be reported in FR 2052a, and the LCR calculation will convert Open to day 1 pursuant to section 31(a)(4) of the LCR Rule.
"""


def build_outflow_adjustment_section() -> str:
    """Hand-formatted Outflow Adjustment Percentage table from page 111."""
    return """\
## Outflow Adjustment Percentage Example

Banking organizations subject to LCR requirements should determine their
category of standards under the LCR rule and apply the appropriate outflow
adjustment percentage.

| Category | Outflow adjustment percentage |
|----------|-------------------------------|
| Global systemically important BHC or GSIB depository institution | 100 percent |
| Category II Board-regulated institution | 100 percent |
| Category III Board-regulated institution with $75 billion or more in average weighted short-term wholesale funding and any Category III Board-regulated institution that is a consolidated subsidiary of such a Category III Board-regulated institution | 100 percent |
| Category III Board-regulated institution with less than $75 billion in average weighted short-term wholesale funding and any Category III Board-regulated institution that is a consolidated subsidiary of such a Category III Board-regulated institution | 85 percent |
| Category IV Board-regulated institution with $50 billion or more in average weighted short-term wholesale funding | 70 percent |

Throughout the mapping tables on the following pages, "HQLA", "Non-HQLA",
and "Other" collateral classes are defined as follows:

- **HQLA** refers to all asset classes listed in Appendix III with a "-Q" suffix.
- **Non-HQLA** refers to all asset classes listed in Appendix III that are not included in "Other" or HQLA.
- **Other** includes the following collateral classes only: C-1, P-1, P-2, LC-1, LC-2 and Z-1.
"""


def extract_table_pages(pdf) -> str:
    """Extract pages 112-179 as structured markdown (skip page 111 which is hand-formatted)."""
    sections = []

    for pg_idx in range(111, 179):  # 0-indexed; skip page 111 (idx 110)
        page = pdf.pages[pg_idx]
        text = (page.extract_text() or "").strip()
        if not text:
            continue
        # Remove trailing page numbers (last line is just a number)
        lines = text.split("\n")
        if lines and re.match(r"^\d+$", lines[-1].strip()):
            lines = lines[:-1]
        sections.append("\n".join(lines))

    return "\n\n".join(sections)


def format_mapping_tables(raw_text: str) -> str:
    """Convert the raw extracted text into structured markdown sections."""
    lines = raw_text.split("\n")
    output = []
    in_provision = False

    SECTION_HEADERS = {
        "HQLA Amount Values",
        "HQLA Additive Values",
        "HQLA Subtractive Values",
        "OUTFLOW VALUES",
        "INFLOW VALUES",
    }

    in_table = False

    for line in lines:
        stripped = line.strip()
        if not stripped:
            if not in_table:
                output.append("")
            continue

        # Numbered provision headers like "(1) High-Quality Liquid Assets (Subpart C, §.20-.22)"
        provision_match = re.match(r"^\((\d+)\)\s+(.+)$", stripped)
        if provision_match:
            num = provision_match.group(1)
            title = provision_match.group(2)
            in_table = False
            output.append("")
            output.append(f"### ({num}) {title}")
            in_provision = True
            continue

        # Continuation of a provision header (e.g., "(§.32(i)(1))" on a new line)
        if stripped.startswith("(§.") and output and output[-1].startswith("### ("):
            output[-1] = output[-1] + " " + stripped
            continue

        # Section headers
        if stripped in SECTION_HEADERS or (stripped.isupper() and re.match(r"^[A-Z][A-Z\s\-]+$", stripped)):
            in_table = False
            output.append("")
            output.append(f"## {stripped}")
            output.append("")
            continue

        # "Field Value" header row
        if stripped == "Field Value":
            output.append("")
            output.append("| Field | Value |")
            output.append("|-------|-------|")
            in_table = True
            continue

        # Field/Value lines
        if in_provision and stripped != "Field Value":
            field_val = split_field_value(stripped)
            if field_val:
                field, value = field_val
                field = field.replace("|", "\\|")
                value = value.replace("|", "\\|")
                output.append(f"| {field} | {value} |")
            else:
                # Continuation line: append to the most recent table row's
                # value, looking past any intervening blank lines (page breaks)
                escaped = stripped.replace("|", "\\|")
                joined = False
                for j in range(len(output) - 1, max(len(output) - 4, -1), -1):
                    if output[j].startswith("| ") and output[j].endswith(" |"):
                        output[j] = output[j][:-2] + " " + escaped + " |"
                        joined = True
                        break
                    elif output[j] == "":
                        continue
                    else:
                        break
                if not joined:
                    output.append(stripped)

    return "\n".join(output)


# Values that appear at the end of field lines
VALUE_PATTERNS = [
    r"\*$",
    r"#$",
    r"NULL$",
    r"(?:Y|N)$",
    r"LCR Firm$",
    r"Matches PID$",
    r"Open.*$",
]

# Known field names (left column)
KNOWN_FIELDS = {
    "Reporting Entity", "PID", "Product", "Sub-Product", "Sub‐Product",
    "Market Value", "Lendable Value", "Maturity Bucket", "Maturity Amount",
    "Maturity Optionality", "Effective Maturity Bucket",
    "Forward Start Amount", "Forward Start Bucket",
    "Collateral Class", "Collateral Value", "Treasury Control",
    "Accounting Designation", "Encumbrance Type", "Internal",
    "Internal Counterparty", "Unencumbered", "Risk Weight",
    "Business Line", "Settlement", "Counterparty", "G-SIB", "G‐SIB",
    "Insured", "Trigger", "Rehypothecated", "Loss Absorbency",
}


def split_field_value(line: str) -> tuple[str, str] | None:
    """Try to split a line into (field_name, value) for the mapping table."""
    # Check for known field names at the start
    for field in KNOWN_FIELDS:
        if line.startswith(field):
            rest = line[len(field):].strip()
            if rest:
                return (field, rest)
            return None

    # Fall back to heuristic: value is the last word/token if it's a known value
    # pattern (*, #, NULL, Y, N, etc.)
    parts = line.rsplit(None, 1)
    if len(parts) == 2:
        potential_value = parts[1]
        if potential_value in ("*", "#", "NULL", "Y", "N"):
            return (parts[0], potential_value)

    # Multi-word values at the end
    for pattern in [
        r"^(.+?)\s+(LCR Firm)$",
        r"^(.+?)\s+(Matches PID)$",
        r"^(.+?)\s+(Open.*)$",
    ]:
        m = re.match(pattern, line)
        if m:
            return (m.group(1), m.group(2))

    return None


def main():
    if sys.stdout.encoding != "utf-8":
        sys.stdout.reconfigure(encoding="utf-8")

    pdf = pdfplumber.open(str(PDF))

    # Build the full document
    parts = []
    parts.append("# Appendix VI: LCR to FR 2052a Mapping")
    parts.append("")
    parts.append("> **Hand-curated.** The LCR formulas on pages 108–109 of the source PDF")
    parts.append("> use Cambria Math font subsets with a broken ToUnicode CMap (each glyph")
    parts.append("> maps to a doubled, incorrect math-italic codepoint). Formula text was")
    parts.append("> transcribed from 12 CFR 249 and the visible document structure.")
    parts.append("> See [`human-annotations.md`](../../human-annotations.md) for details.")
    parts.append(">")
    parts.append("> Mapping tables (pages 111–179) extracted via `pdfplumber.extract_text()`.")
    parts.append("")

    # Intro text (page 108, before formulas)
    parts.append("Staff of the Board of Governors of the Federal Reserve System (Board) "
                 "has developed this document to assist reporting firms subject to the "
                 "liquidity coverage ratio rule (LCR Rule[^1]) in mapping the provisions "
                 "of the LCR Rule to the unique data identifiers reported on FR 2052a. "
                 "This mapping document is not a part of the LCR Rule nor a component "
                 "of the FR 2052a report. Firms may use this mapping document solely at "
                 "their discretion. From time to time, to ensure accuracy, an updated "
                 "mapping document may be published and reporting firms will be notified "
                 "of these changes.")
    parts.append("")

    # Key
    parts.append("## Key")
    parts.append("")
    parts.append("| Symbol | Meaning |")
    parts.append("|--------|---------|")
    parts.append("| `*` | Values relevant to the LCR |")
    parts.append("| `#` | Values not relevant to the LCR |")
    parts.append("| `NULL` | Should not have an associated value |")
    parts.append("")

    # Formulas
    parts.append(build_formula_section())

    # Outflow Adjustment Percentage (page 111)
    parts.append(build_outflow_adjustment_section())

    # Table pages (112-179)
    raw_tables = extract_table_pages(pdf)
    formatted = format_mapping_tables(raw_tables)
    parts.append(formatted)

    pdf.close()

    # Write output
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(parts), encoding="utf-8")
    print(f"Wrote {OUT}")
    print(f"  ({len(parts)} parts, {sum(len(p) for p in parts)} chars)")


if __name__ == "__main__":
    main()
