"""
One-shot extractor for Appendix II-c (FR 2052a Collateral Class Requirements).

The check marks in this appendix are Wingdings glyphs (U+F0FC) drawn in
specific columns: Required / Dependent / Not Applicable. Plain pdftotext
loses the column information because the glyph appears in column-shifted
positions on each page. We use pdfplumber to read characters with their
absolute x-coordinates, then bucket each Wingdings glyph into a column
using the page's own header label positions.

Section headings (e.g. "Inflows - Assets") are emitted as a separator
between the rows of each table.

Pages: PDF 92-95 (corresponds to doc pages 91-94).

Usage:
    python extract_iic.py
"""

from __future__ import annotations

import collections
import re
import sys
from pathlib import Path

import pdfplumber

# A row begins with a PID like "I.A.1", "S.DC.21", "O.W.10" — uppercase
# letters / digits separated by dots, followed by a space. Anything that
# does NOT match this pattern is treated as a section heading.
PID_RE = re.compile(r"^[A-Z]+(?:\.[A-Z]+)?\.\d+ ")

PDF = Path(__file__).resolve().parents[2] / "raw" / "FR_2052a20250226_f.pdf"
PAGES = range(92, 96)  # 1-indexed PDF pages

ROW_TOL = 6.0     # vertical distance to group chars into the same row
WING_FONT = "Wingdings"


def extract_page(page) -> tuple[list[tuple[float, float, float]], list[tuple[float, str]]]:
    """Return (column_centres, rows) for a page.

    column_centres = [(x_required, x_dependent, x_notapp)] derived from the
        header row.
    rows = list of (y, "PID Product label", classification) where
        classification is "Required" / "Dependent" / "Not Applicable" / "" for
        section headings.
    """
    by_y: dict[int, list] = collections.defaultdict(list)
    for c in page.chars:
        by_y[round(c["top"])].append(c)

    # Locate the header row.
    header_y = None
    header_xs = {}
    for y in sorted(by_y.keys()):
        cs = sorted(by_y[y], key=lambda c: c["x0"])
        text = "".join(c["text"] for c in cs)
        if "Required" in text and "Dependent" in text and "Not Applicable" in text:
            header_y = y
            for label in ("Required", "Dependent", "Not Applicable"):
                i = text.index(label)
                x0 = cs[i]["x0"]
                x1 = cs[i + len(label) - 1]["x1"]
                header_xs[label] = (x0, x1)
            break
    if header_y is None:
        sys.exit(f"could not locate header on page {page.page_number}")

    # Compute column boundaries: midpoints between consecutive header centres.
    req_c = sum(header_xs["Required"]) / 2
    dep_c = sum(header_xs["Dependent"]) / 2
    na_c = sum(header_xs["Not Applicable"]) / 2
    # Boundary = midpoint between centres.
    b1 = (req_c + dep_c) / 2
    b2 = (dep_c + na_c) / 2

    def classify(x: float) -> str:
        if x < b1:
            return "Required"
        if x < b2:
            return "Dependent"
        return "Not Applicable"

    # Walk text rows after the header. Use a wider tolerance to merge
    # text-baseline y with Wingdings-baseline y on the same visual row.
    chars = sorted(page.chars, key=lambda c: (c["top"], c["x0"]))
    visible = [c for c in chars if c["top"] > header_y + 3]

    # Bucket chars by visual row (cluster by top within ROW_TOL).
    rows_chars: list[list] = []
    for c in visible:
        if rows_chars and abs(c["top"] - rows_chars[-1][0]["top"]) <= ROW_TOL:
            rows_chars[-1].append(c)
        else:
            rows_chars.append([c])

    out_rows = []
    for cs in rows_chars:
        cs_sorted = sorted(cs, key=lambda c: c["x0"])
        # Text content sits left of the "Required" column header. Use a
        # threshold a few pixels in from the header start so long product
        # names like S.L.4 are not truncated.
        text_chars = [c for c in cs_sorted if WING_FONT not in c["fontname"]
                      and c["x0"] < 378]
        wing_chars = [c for c in cs_sorted if WING_FONT in c["fontname"]]
        text = "".join(c["text"] for c in text_chars).strip()
        if not text:
            continue
        if "Page" in text and "of 106" in text:
            continue
        if text.startswith("FR 2052a Instructions"):
            continue
        # Insert a single space between PID and product name (chars often
        # touch). We do this by detecting a transition between
        # Calibri-Italic (PID) and Calibri (product name).
        text = _split_pid_product(text_chars)
        if not wing_chars:
            classification = ""  # section heading
        else:
            classification = classify(wing_chars[0]["x0"])
        out_rows.append((cs[0]["top"], text, classification))

    return out_rows


def _split_pid_product(chars) -> str:
    """Insert a single space between the PID prefix (italic) and the product
    name (regular)."""
    out: list[str] = []
    prev_italic = None
    for c in chars:
        is_italic = "Italic" in c["fontname"]
        if prev_italic is True and is_italic is False and out and out[-1] != " ":
            out.append(" ")
        out.append(c["text"])
        prev_italic = is_italic
    return "".join(out).strip()


SECTION_BY_PREFIX = {
    "I.A.": "Inflows - Assets",
    "I.U.": "Inflows - Unsecured",
    "I.S.": "Inflows - Secured",
    "I.O.": "Inflows - Other",
    "O.W.": "Outflows - Wholesale",
    "O.S.": "Outflows - Secured",
    "O.D.": "Outflows - Deposits",
    "O.O.": "Outflows - Other",
    "S.DC.": "Supplemental - Derivatives & Collateral",
    "S.L.": "Supplemental - Liquidity Risk Measurement",
    "S.B.": "Supplemental - Balance Sheet",
    "S.I.": "Supplemental - Informational",
    "S.FX.": "Supplemental - Foreign Exchange",
}


def section_for(pid: str) -> str:
    for prefix, name in SECTION_BY_PREFIX.items():
        if pid.startswith(prefix):
            return name
    return ""


def main() -> None:
    # Force UTF-8 stdout on Windows so the ✓ glyph renders.
    sys.stdout.reconfigure(encoding="utf-8")
    all_rows: list[tuple[str, str, str, str]] = []  # (section, pid, product, class)
    current_section = ""
    with pdfplumber.open(PDF) as pdf:
        for page_num in PAGES:
            page = pdf.pages[page_num - 1]
            rows = extract_page(page)
            for _, text, cls in rows:
                # Distinguish a product row from a section heading by whether
                # the text begins with a PID code. Section headings don't.
                if not PID_RE.match(text):
                    current_section = text
                    continue
                # Split PID and product.
                parts = text.split(" ", 1)
                if len(parts) != 2:
                    continue
                pid, product = parts[0], parts[1]
                # Re-derive the section from the PID for safety; fall back to
                # the visually-detected current_section.
                section = section_for(pid) or current_section
                all_rows.append((section, pid, product, cls))

    # Print as Markdown. Section name appears as a bolded heading row above
    # each section's products.
    print("| PID | Product | Required | Dependent | Not Applicable |")
    print("|---|---|:--:|:--:|:--:|")
    last_section: str | None = None
    for section, pid, product, cls in all_rows:
        if section != last_section:
            print(f"| **{section}** | | | | |")
            last_section = section
        cells = ["", "", ""]
        if cls == "Required":
            cells[0] = "✓"
        elif cls == "Dependent":
            cells[1] = "✓"
        elif cls == "Not Applicable":
            cells[2] = "✓"
        print(f"| {pid} | {product} | {cells[0]} | {cells[1]} | {cells[2]} |")


if __name__ == "__main__":
    main()
