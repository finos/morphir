"""
Extractor for Appendix VIII (NSFR to FR 2052a Mapping).

Pages 195-253 of the PDF (1-indexed). The NSFR formulas on pages 195-196
use the same broken ToUnicode CMap as Appendix VI (Cambria/CambriaMath
font subsets that map multiple glyphs to the same doubled math-italic
codepoint), so formula text is irrecoverable via text extraction. We
transcribe those from the NSFR Rule (12 CFR 249 §.100-§.109) and the
visible structure of the garbled output.

Pages 197-253 contain:
  - ASF Amount Values (provisions 1-44)
  - RSF Amount Values (provisions 45-101)
  - Calculation of NSFR derivatives amounts (provisions 102-113)
  - Rules for consolidation (provision 114)

The mapping provisions extract cleanly via pdfplumber.extract_text().

Usage:
    python structured/scripts/extract_viii.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pdfplumber

PDF = Path(__file__).resolve().parents[2] / "raw" / "FR_2052a20250226_f.pdf"
OUT = Path(__file__).resolve().parents[1] / "output" / "04-appendices" / "VIII-nsfr-mapping.md"

FORMULA_PAGES = range(195, 197)    # pages 195-196
TABLE_PAGES = range(197, 254)      # pages 197-253


def build_intro_and_key() -> str:
    """Hand-formatted intro paragraph and Reference Key from page 195."""
    return """\
Staff of the Board of Governors of the Federal Reserve System (Board)
has developed this document to assist reporting firms subject to the
Liquidity Risk Measurement Standards (LRM standards)[^1] in mapping the
provisions applicable to the Net Stable Funding Ratio (NSFR) to the
unique data identifiers reported on FR 2052a. This mapping document is
not a part of the LRM Standards nor a component of the FR 2052a report.
Firms may use this mapping document solely at their discretion. From
time to time, to ensure accuracy, an updated mapping document may be
published and reporting firms will be notified of these changes.

## Reference Key

| Reference | Meaning |
|-----------|---------|
| `*` | Values relevant to the NSFR (e.g., value field aggregated to determine ASF or RSF amount) |
| `#` | Values not relevant to the NSFR |
| `NULL` | Should not have an associated value |
| Level 1 HQLA | [Collateral Class] values of: A-0-Q, A-1-Q, A-2-Q, A-3-Q, A-4-Q, A-5-Q, S-1-Q, S-2-Q, S-3-Q, S-4-Q, CB-1-Q, CB-2-Q |
| Level 2A HQLA | [Collateral Class] values of: G-1-Q, G-2-Q, G-3-Q, S-5-Q, S-6-Q, S-7-Q, CB-3-Q |
| Level 2B HQLA | [Collateral Class] values of: E-1-Q, E-2-Q, IG-1-Q, IG-2-Q |
| HQLA | [Collateral Class] values listed in Level 1, Level 2A and Level 2B HQLA above |
| Financial Sector Entity | [Counterparty] values of: Pension Fund, Bank, Broker-Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non-Bank Financial Entity, Non-Regulated Fund |
| Non-Financial Wholesale Entity | [Counterparty] values of: Non-Financial Corporate, Sovereign, Government Sponsored Entity, Public Sector Entity, Multilateral Development Bank, Other Supranational, Debt Issuing SPE, Other |

[^1]: Refer to LRM Standards as defined in the FR 2052a instructions.
"""


def build_formula_section() -> str:
    """Hand-transcribed from 12 CFR 249 §.100-§.109 and the mapping document structure.

    The formulas on pages 195-196 use the same broken Cambria Math font as
    Appendix VI. The decoded structure (with mapping table ID references)
    was reconstructed from the garbled pdfplumber output and the regulatory
    text.
    """
    return """\
## NSFR Calculation

```
NSFR = ASF amount / RSF amount

ASF amount = SUM(ASF Amount Values_a * ASF factor_a)
    - Deduction of non-transferrable excess subsidiary stable funding (§.109)

Where "a" corresponds to each mapping table ID in the ASF Amount Values below

RSF amount = Net derivatives RSF amount + Derivatives RSF amount

Net derivatives RSF amount = SUM(RSF Amount Values_r * RSF factor_r)

Where "r" corresponds to each mapping table ID in the RSF Amount Values
section below, excluding the subsection "Calculation of NSFR derivatives
amounts (§.107)".

Derivatives RSF amount
    = Current replacement cost RSF amount * 1 + Potential derivative charges * 0.05
    + (Counterparties at CCP mutualized loss sharing arrangements
       + Initial margin provided) * 0.85
    + Additional RSF for 100% RSF assets pledged for IM and DFC * 0.15

Current replacement cost RSF amount = MAX[0, (i_110 - i_111) - (i_112 - i_113)]

Potential derivative charges = i_102 + i_103

Counterparties at CCP mutualized loss sharing arrangements + Initial margin provided
    = i_104 + i_105

                                                            109
Additional RSF for 100% RSF assets pledged for IM and DFC = SUM(i_i)
                                                            i=106

Where "i" refers to a mapping table ID below corresponding to the specific subscript
```
"""


def build_rules_of_construction() -> str:
    """Hand-formatted Rules of construction (§.102) from page 196."""
    return """\
## Rules of construction (§.102)

To conform to the accounting balance sheet and accommodate the netting of
certain transactions permissible under §.102(b), the FR 2052a includes
two products that should be used to adjust the gross balances mapped to
the ASF and RSF tables in this document.

- For securities financing transactions, negative [Maturity Amount]
  values should be reported using product S.B.5: Counterparty Netting to
  reduce the ASF and RSF tables below corresponding to secured funding
  and lending transactions where the criteria referenced in §.102(b) are
  met.

- For all other components of the balance sheet, positive or negative
  [Market Value] or [Maturity Amount] values should be reported using
  product S.B.6: Carrying Value Adjustment to increase or decrease the
  cumulative values otherwise reported under FR 2052a products such that
  the cumulative total including these adjustments aligns with the
  balance sheet carrying value. Examples could include: adjustments to
  the [Market Value] of securities to align with the book value (e.g.,
  for positions booked as held-to-maturity); adjustments to reduce the
  [Maturity Amount] of interest and dividend payable and receivable
  amounts to align with accrued interest accounts represented on the
  balance sheet; and adjustments to the [Maturity Amount] of loans that
  are accounted for at fair value.

In both cases, the additional fields in the S.B table structure should be
used to appropriately map these adjustments to each respective ASF and
RSF element identified in the mapping tables below.
"""


KNOWN_FIELDS = {
    "Reporting Entity", "PID", "Product", "Sub-Product", "Sub‐Product",
    "Sub-Product2", "Sub‐Product2",
    "Product Reference", "Sub-Product Reference", "Sub‐Product Reference",
    "Collection Reference",
    "Market Value", "Lendable Value", "Maturity Bucket", "Maturity Amount",
    "Maturity Optionality", "Effective Maturity Bucket",
    "Forward Start Amount", "Forward Start Bucket",
    "Collateral Class", "Collateral Value", "Collateral Level",
    "Treasury Control", "Accounting Designation", "Encumbrance Type",
    "Internal", "Internal Counterparty", "Unencumbered", "Risk Weight",
    "Business Line", "Settlement", "Counterparty", "G-SIB", "G‐SIB",
    "Insured", "Trigger", "Rehypothecated", "Loss Absorbency",
    "Netting Eligible", "Converted",
}

_SORTED_FIELDS = sorted(KNOWN_FIELDS, key=len, reverse=True)

SECTION_HEADERS = {
    "ASF Amount Values",
    "RSF Amount Values",
}

ASF_FACTOR_RE = re.compile(
    r"^NSFR (?:regulatory capital elements and NSFR )?liabilities assigned a .+ ASF factor"
)
RSF_FACTOR_RE = re.compile(
    r"^Unencumbered assets(?: and commitments)? assigned a[n]? .+ RSF factor"
)
CALC_HEADER_RE = re.compile(
    r"^Calculation of NSFR derivatives amounts"
)
RULES_HEADER_RE = re.compile(
    r"^Rules for consolidation"
)


def split_field_value(line: str) -> tuple[str, str] | None:
    """Try to split a line into (field_name, value) for the mapping table."""
    for field in _SORTED_FIELDS:
        if line == field:
            return (field, "")
        if line.startswith(field + " "):
            rest = line[len(field):].strip()
            return (field, rest)

    parts = line.rsplit(None, 1)
    if len(parts) == 2 and parts[1] in ("*", "#", "NULL", "Y", "N"):
        candidate = parts[0]
        if "," not in candidate:
            return (candidate, parts[1])

    for pattern in [
        r"^(.+?)\s+(NSFR Entity)$",
        r"^(.+?)\s+(Matches PID)$",
        r"^(.+?)\s+(Open.*)$",
    ]:
        m = re.match(pattern, line)
        if m:
            return (m.group(1), m.group(2))

    return None


def extract_table_pages(pdf) -> str:
    """Extract pages 197-253 as raw text, stripping trailing page numbers."""
    sections = []

    for pg_num in TABLE_PAGES:
        page = pdf.pages[pg_num - 1]
        text = (page.extract_text() or "").strip()
        if not text:
            continue
        lines = text.split("\n")
        if lines and re.match(r"^\d+$", lines[-1].strip()):
            lines = lines[:-1]
        sections.append("\n".join(lines))

    return "\n\n".join(sections)


def format_mapping_tables(raw_text: str) -> str:
    """Convert the raw extracted text into structured markdown sections."""
    lines = raw_text.split("\n")
    output: list[str] = []
    in_provision = False
    in_table = False

    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        i += 1

        if not stripped:
            if not in_table:
                output.append("")
            continue

        # Bare section-reference continuation: "(§.104(a))" after a header
        if re.match(r"^\(§\.\d+", stripped) and not re.match(r"^\(\d+\)\s+", stripped):
            for j in range(len(output) - 1, max(len(output) - 4, -1), -1):
                if output[j].startswith("**") and output[j].endswith("**"):
                    output[j] = output[j][:-2] + " " + stripped + "**"
                    break
                elif output[j].startswith("### ("):
                    output[j] = output[j] + " " + stripped
                    break
                elif output[j] == "":
                    continue
                else:
                    break
            continue

        # Numbered provision headers: "(1) NSFR regulatory capital element (§.104(a)(1))"
        provision_match = re.match(r"^\((\d+)\)\s+(.+)$", stripped)
        if provision_match:
            num = provision_match.group(1)
            title = provision_match.group(2)
            in_table = False
            in_provision = True
            output.append("")
            output.append(f"### ({num}) {title}")
            continue

        # Continuation of provision header on next line (before the Field Value row)
        if in_provision and not in_table and output and output[-1].startswith("### ("):
            if stripped != "Field Value" and not split_field_value(stripped):
                output[-1] = output[-1] + " " + stripped
                continue

        # Top-level section headers
        if stripped in SECTION_HEADERS:
            in_table = False
            in_provision = False
            output.append("")
            output.append(f"## {stripped}")
            output.append("")
            continue

        # ASF/RSF factor grouping headers
        if ASF_FACTOR_RE.match(stripped) or RSF_FACTOR_RE.match(stripped):
            in_table = False
            output.append("")
            output.append(f"**{stripped}**")
            output.append("")
            continue

        # Calculation of NSFR derivatives header
        if CALC_HEADER_RE.match(stripped):
            in_table = False
            output.append("")
            output.append(f"**{stripped}**")
            output.append("")
            continue

        # Rules for consolidation header
        if RULES_HEADER_RE.match(stripped):
            in_table = False
            output.append("")
            output.append(f"**{stripped}**")
            output.append("")
            continue

        # "Field Value" header row
        if stripped == "Field Value":
            output.append("")
            output.append("| Field | Value |")
            output.append("|-------|-------|")
            in_table = True
            continue

        # Footnotes (lines starting with a digit followed by space and text)
        footnote_match = re.match(r'^(\d+)\s+(Refer to|The tables|Overcollateralized|["“]Overcollateralized|In general)', stripped)
        if footnote_match:
            fn_num = footnote_match.group(1)
            fn_text = stripped[len(fn_num):].strip()
            # Look ahead for continuation lines
            while i < len(lines) and lines[i].strip() and not re.match(r"^\(?\d+\)?[\s)]", lines[i].strip()) and lines[i].strip() != "Field Value":
                next_line = lines[i].strip()
                if next_line in SECTION_HEADERS or ASF_FACTOR_RE.match(next_line):
                    break
                fn_text += " " + next_line
                i += 1
            in_table = False
            output.append("")
            output.append(f"[^{fn_num}]: {fn_text}")
            continue

        # Field/Value lines inside a provision
        if in_provision:
            fv = split_field_value(stripped)
            if fv:
                field, value = fv
                field = field.replace("|", "\\|")
                value = value.replace("|", "\\|")
                output.append(f"| {field} | {value} |")
                in_table = True
            else:
                # Continuation line: append to the most recent table row
                escaped = stripped.replace("|", "\\|")
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
                    output.append(stripped)
            continue

        # Anything else: emit as prose
        output.append(stripped)

    return "\n".join(output)


def main():
    if sys.stdout.encoding != "utf-8":
        sys.stdout.reconfigure(encoding="utf-8")

    pdf = pdfplumber.open(str(PDF))

    parts: list[str] = []
    parts.append("# Appendix VIII: NSFR to FR 2052a Mapping")
    parts.append("")
    parts.append("> **Hand-curated.** The NSFR formulas on pages 195–196 of the source PDF")
    parts.append("> use Cambria Math font subsets with a broken ToUnicode CMap (same issue")
    parts.append("> as Appendix VI). Formula text was transcribed from 12 CFR 249 §.100–§.109")
    parts.append("> and the visible document structure.")
    parts.append("> See [`human-annotations.md`](../../human-annotations.md) for details.")
    parts.append(">")
    parts.append("> Mapping tables (pages 197–253) extracted via `pdfplumber.extract_text()`.")
    parts.append("")

    parts.append(build_intro_and_key())
    parts.append(build_formula_section())
    parts.append(build_rules_of_construction())

    # Mapping tables (pages 197-253)
    raw_tables = extract_table_pages(pdf)
    formatted = format_mapping_tables(raw_tables)
    parts.append(formatted)

    pdf.close()

    OUT.parent.mkdir(parents=True, exist_ok=True)
    out_text = "\n".join(parts) + "\n"
    OUT.write_text(out_text, encoding="utf-8")
    print(f"Wrote {OUT}")
    line_count = out_text.count("\n")
    char_count = len(out_text)
    print(f"  {line_count} lines, {char_count} chars")


if __name__ == "__main__":
    main()
