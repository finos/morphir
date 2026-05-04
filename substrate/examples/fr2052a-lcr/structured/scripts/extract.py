"""
Extract FR 2052a Instructions PDF into a set of Markdown files.

Pipeline:
  raw/FR_2052a20250226_f.pdf
    -> pdftotext -layout -enc UTF-8 -> intermediate text
    -> Python splitter (this script) -> output/*.md

Run from the examples/fr2052a-lcr directory:
    python structured/scripts/extract.py

Output goes to structured/output/. The intermediate text file is kept at
structured/scripts/_full.txt for debugging.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # examples/fr2052a-lcr
PDF = ROOT / "raw" / "FR_2052a20250226_f.pdf"
INTERMEDIATE = ROOT / "structured" / "scripts" / "_full.txt"
OUT = ROOT / "structured" / "output"


# ---------------------------------------------------------------------------
# Step 1: run pdftotext to produce a layout-preserving UTF-8 text dump.
# ---------------------------------------------------------------------------

def run_pdftotext() -> str:
    if shutil.which("pdftotext") is None:
        sys.exit("pdftotext not found on PATH. Install poppler-utils / xpdf.")
    INTERMEDIATE.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["pdftotext", "-layout", "-enc", "UTF-8", str(PDF), str(INTERMEDIATE)],
        check=True,
    )
    # Some pdftotext builds occasionally emit a stray non-UTF-8 byte in
    # ligature glyphs; replace rather than crash.
    return INTERMEDIATE.read_bytes().decode("utf-8", errors="replace")


# ---------------------------------------------------------------------------
# Step 2: clean running headers / footers / page numbers.
# ---------------------------------------------------------------------------

PAGE_HEADER = re.compile(r"^\s*FR 2052a Instructions\s*$")
PAGE_FOOTER_MAIN = re.compile(r"^\s*Page \d+ of 106\s*$")
PAGE_NUM_ONLY = re.compile(r"^\s*\d{1,3}\s*$")  # bare numbers in enclosure appendices


def strip_running_chrome(lines: list[str]) -> list[str]:
    """Remove repeating page header/footer noise from the raw layout dump."""
    cleaned: list[str] = []
    for ln in lines:
        if PAGE_HEADER.match(ln):
            continue
        if PAGE_FOOTER_MAIN.match(ln):
            continue
        cleaned.append(ln)
    # Collapse 3+ consecutive blank lines to 2.
    out: list[str] = []
    blanks = 0
    for ln in cleaned:
        if ln.strip() == "":
            blanks += 1
            if blanks <= 2:
                out.append("")
        else:
            blanks = 0
            out.append(ln)
    return out


# ---------------------------------------------------------------------------
# Step 3: section map.
#
# Each entry: (exact-line-match, output-relative-path, h1-title)
# The order MUST match document order; the splitter slices the cleaned text
# from one anchor to the next.
# ---------------------------------------------------------------------------


@dataclass
class Section:
    anchor: str                         # exact match on a single cleaned line
    path: str                           # path relative to OUT
    title: str                          # H1 title for the file
    kind: str = "prose"                 # "prose" | "appendix"
    body: list[str] = field(default_factory=list)


# Files that are hand-curated (with the help of human visual annotations in
# structured/human-annotations.md). The splitter must NOT overwrite these on
# re-run.
MANUAL_CURATION: set[str] = {
    "04-appendices/I-data-format.md",
    "04-appendices/II-a-product-subproduct-requirements.md",
    "04-appendices/II-b-counterparty-requirements.md",
    "04-appendices/II-c-collateral-class-requirements.md",
    "04-appendices/II-d-forward-start-exclusions.md",
    "04-appendices/III-asset-category-table.md",
    "04-appendices/IV-a-maturity-bucket-value-list.md",
    "04-appendices/IV-b-maturity-bucket-tailoring.md",
    "04-appendices/V-double-counting.md",
    "04-appendices/VI-lcr-mapping.md",
    "04-appendices/VII-stwf-mapping.md",
    "04-appendices/VIII-nsfr-mapping.md",
}


SECTIONS: list[Section] = [
    Section("General Instructions",
            "01-general-instructions.md",
            "General Instructions"),
    Section("Field Definitions",
            "02-field-definitions.md",
            "Field Definitions"),
    # Product Definitions is split per product group; the "Product Definitions"
    # heading itself becomes an intro file.
    Section("Product Definitions",
            "03-product-definitions/00-overview.md",
            "Product Definitions"),
    Section("I.A: Inflows-Assets",
            "03-product-definitions/I.A-inflows-assets.md",
            "I.A: Inflows-Assets"),
    Section("I.U: Inflows-Unsecured",
            "03-product-definitions/I.U-inflows-unsecured.md",
            "I.U: Inflows-Unsecured"),
    Section("I.S: Inflows-Secured",
            "03-product-definitions/I.S-inflows-secured.md",
            "I.S: Inflows-Secured"),
    Section("I.O: Inflows-Other",
            "03-product-definitions/I.O-inflows-other.md",
            "I.O: Inflows-Other"),
    Section("O.W: Outflows-Wholesale",
            "03-product-definitions/O.W-outflows-wholesale.md",
            "O.W: Outflows-Wholesale"),
    Section("O.S: Outflows-Secured",
            "03-product-definitions/O.S-outflows-secured.md",
            "O.S: Outflows-Secured"),
    Section("O.D: Outflows-Deposits",
            "03-product-definitions/O.D-outflows-deposits.md",
            "O.D: Outflows-Deposits"),
    Section("O.O: Outflows-Other",
            "03-product-definitions/O.O-outflows-other.md",
            "O.O: Outflows-Other"),
    Section("S.DC: Supplemental-Derivatives & Collateral",
            "03-product-definitions/S.DC-supplemental-derivatives-collateral.md",
            "S.DC: Supplemental — Derivatives & Collateral"),
    Section("S.L: Supplemental-Liquidity Risk Measurement (LRM)",
            "03-product-definitions/S.L-supplemental-lrm.md",
            "S.L: Supplemental — Liquidity Risk Measurement (LRM)"),
    Section("S.B: Supplemental-Balance Sheet",
            "03-product-definitions/S.B-supplemental-balance-sheet.md",
            "S.B: Supplemental — Balance Sheet"),
    Section("S.I: Supplemental-Informational",
            "03-product-definitions/S.I-supplemental-informational.md",
            "S.I: Supplemental — Informational"),
    Section("S.FX: Supplemental-Foreign Exchange",
            "03-product-definitions/S.FX-supplemental-foreign-exchange.md",
            "S.FX: Supplemental — Foreign Exchange"),
    Section("Appendix I: FR 2052a Data Format, Tables, and Fields",
            "04-appendices/I-data-format.md",
            "Appendix I: FR 2052a Data Format, Tables, and Fields",
            kind="appendix"),
    Section("Appendix II-a: FR 2052a Product/Sub-Product Requirements",
            "04-appendices/II-a-product-subproduct-requirements.md",
            "Appendix II-a: FR 2052a Product/Sub-Product Requirements",
            kind="appendix"),
    Section("Appendix II-b: FR 2052a Counterparty Requirements",
            "04-appendices/II-b-counterparty-requirements.md",
            "Appendix II-b: FR 2052a Counterparty Requirements",
            kind="appendix"),
    Section("Appendix II-c: FR 2052a Collateral Class Requirements",
            "04-appendices/II-c-collateral-class-requirements.md",
            "Appendix II-c: FR 2052a Collateral Class Requirements",
            kind="appendix"),
    Section("Appendix II-d: FR 2052a Forward Start Exclusions",
            "04-appendices/II-d-forward-start-exclusions.md",
            "Appendix II-d: FR 2052a Forward Start Exclusions",
            kind="appendix"),
    Section("Appendix III: FR 2052a Asset Category Table",
            "04-appendices/III-asset-category-table.md",
            "Appendix III: FR 2052a Asset Category Table",
            kind="appendix"),
    Section("Appendix IV-a: FR 2052a Maturity Bucket Value List",
            "04-appendices/IV-a-maturity-bucket-value-list.md",
            "Appendix IV-a: FR 2052a Maturity Bucket Value List",
            kind="appendix"),
    Section("Appendix IV-b: FR 2052a Maturity Bucket Tailoring",
            "04-appendices/IV-b-maturity-bucket-tailoring.md",
            "Appendix IV-b: FR 2052a Maturity Bucket Tailoring",
            kind="appendix"),
    Section("Appendix V: FR 2052a Double Counting of Certain Exposures",
            "04-appendices/V-double-counting.md",
            "Appendix V: FR 2052a Double Counting of Certain Exposures",
            kind="appendix"),
    # Enclosed mapping documents — separate page-numbered PDFs concatenated
    # into the same file. The header lines vary in spacing, so we match by a
    # forgiving prefix in find_section_starts().
    Section("APPENDIX VI: LCR to FR 2052a Mapping",
            "04-appendices/VI-lcr-mapping.md",
            "Appendix VI: LCR to FR 2052a Mapping",
            kind="appendix"),
    Section("APPENDIX VII: Short-Term Wholesale Funding (STWF) to FR 2052a Mapping",
            "04-appendices/VII-stwf-mapping.md",
            "Appendix VII: Short-Term Wholesale Funding (STWF) to FR 2052a Mapping",
            kind="appendix"),
    Section("APPENDIX VIII: NSFR to FR 2052a Mapping",
            "04-appendices/VIII-nsfr-mapping.md",
            "Appendix VIII: NSFR to FR 2052a Mapping",
            kind="appendix"),
]


def find_section_starts(lines: list[str]) -> list[int]:
    """Return the line index where each SECTIONS entry begins.

    The body section anchors live in the document body (not in the ToC at the
    top). We therefore take the LAST occurrence in document order, walking
    forward from the previous match.
    """
    def norm(s: str) -> str:
        # Collapse Unicode dash variants to ASCII hyphen for matching.
        return (s.replace("‐", "-").replace("‑", "-")
                 .replace("‒", "-").replace("–", "-")
                 .replace("—", "-").replace("−", "-").strip())

    starts: list[int] = []
    cursor = 0
    for sec in SECTIONS:
        target = norm(sec.anchor)
        found = -1
        for i in range(cursor, len(lines)):
            ln = norm(lines[i])
            if ln == target:
                found = i
                break
            if target.startswith("APPENDIX") and ln.endswith(target):
                found = i
                break
        if found < 0:
            sys.exit(f"Could not locate section anchor: {sec.anchor!r}")
        starts.append(found)
        cursor = found + 1
    return starts


# ---------------------------------------------------------------------------
# Step 4: format each section into Markdown.
# ---------------------------------------------------------------------------

# Subsection heading patterns inside Product Definitions.
PRODUCT_HEADING = re.compile(r"^([IOS]\.[A-Z]+(?:\.\d+)?):\s+(.+)$")

# Field-definition headings: a single short line (1-3 words, Title Case),
# preceded by blank, followed by descriptive prose. We don't try to detect
# these from formatting alone; we use a known list extracted from the ToC.
FIELD_TERMS = [
    "Reporting entity", "Currency", "Converted", "Product", "Sub-Product",
    "Counterparty", "Collateral Class", "Collateral Value", "Maturity Bucket",
    "Effective Maturity Bucket", "Maturity Amount", "Forward Start Bucket",
    "Forward Start Amount", "Internal", "Internal Counterparty",
    "Treasury Control", "Market Value", "Lendable Value", "Business Line",
    "Settlement", "Rehypothecated", "Unencumbered", "Insured", "Trigger",
    "Risk Weight", "Collection Reference", "Product Reference",
    "Sub-Product Reference", "Netting Eligible", "Encumbrance Type",
    "Collateral Level", "Accounting Designation", "Loss Absorbency", "G-SIB",
    "Maturity Optionality",
]
FIELD_TERMS_SET = set(FIELD_TERMS)

# General Instructions has its own subsection headings (from the ToC).
GENERAL_TERMS = [
    "Purpose", "Confidentiality", "Liquidity Risk Measurement (LRM) Standards",
    "Undefined Terms", "Who Must Report", "Scope of the Consolidated Entity",
    "Rules of Consolidation", "Frequency and Timing of Data Submission",
    "What Must Be Reported",
]
GENERAL_TERMS_SET = set(GENERAL_TERMS)


def dedent_uniformly(lines: list[str]) -> list[str]:
    """Remove the common left-margin indent (pdftotext -layout pads everything)."""
    nonblank = [ln for ln in lines if ln.strip()]
    if not nonblank:
        return lines
    indent = min(len(ln) - len(ln.lstrip(" ")) for ln in nonblank)
    if indent == 0:
        return lines
    return [ln[indent:] if len(ln) >= indent else ln for ln in lines]


def format_prose(section: Section, body: list[str]) -> str:
    """Format a prose section: convert known sub-headings, bullets, etc."""
    body = dedent_uniformly(body)
    out: list[str] = [f"# {section.title}", ""]

    i = 0
    while i < len(body):
        ln = body[i]
        stripped = ln.strip()

        # Sub-headings inside Field Definitions / General Instructions.
        if (section.path.endswith("02-field-definitions.md")
                and stripped in FIELD_TERMS_SET):
            out.append(f"## {stripped}")
            out.append("")
            i += 1
            continue
        if (section.path.endswith("01-general-instructions.md")
                and stripped in GENERAL_TERMS_SET):
            out.append(f"## {stripped}")
            out.append("")
            i += 1
            continue

        # Product / sub-product headings inside Product Definitions.
        # A real heading is a stand-alone line: previous line blank, name
        # short, no mid-sentence punctuation. This excludes inline references
        # like "...should be reported under, product I.A.2: Capacity. Exclude..."
        m = PRODUCT_HEADING.match(stripped)
        if (m and section.path.startswith("03-product-definitions/")
                and (i == 0 or body[i - 1].strip() == "")
                and ". " not in m.group(2)
                and len(m.group(2)) <= 80):
            pid, name = m.group(1), m.group(2).rstrip(".")
            level = "##" if pid.count(".") == 1 else "###"
            out.append(f"{level} {pid}: {name}")
            out.append("")
            i += 1
            continue

        # Bullets: "• text" possibly wrapped over multiple lines.
        if stripped.startswith("• "):
            out.append(f"- {stripped[2:].strip()}")
            i += 1
            # Continuation lines (indented, no bullet) collapse into the bullet.
            while i < len(body) and body[i].startswith("    ") and not body[i].lstrip().startswith("•"):
                cont = body[i].strip()
                if cont:
                    out[-1] += " " + cont
                else:
                    out.append("")
                    break
                i += 1
            continue

        out.append(ln.rstrip())
        i += 1

    # Trim trailing blanks, ensure single trailing newline.
    while out and out[-1].strip() == "":
        out.pop()
    out.append("")
    return "\n".join(out)


def format_appendix(section: Section, body: list[str]) -> str:
    """Appendices are mostly tables drawn from positioned text. We preserve
    them verbatim in a fenced code block so layout is faithful, and let a
    later pass convert the simpler tables to real Markdown if desired."""
    body = dedent_uniformly(body)
    while body and body[0].strip() == "":
        body.pop(0)
    while body and body[-1].strip() == "":
        body.pop()
    return "\n".join([
        f"# {section.title}",
        "",
        "> Preserved verbatim from the source PDF. Tables in this appendix",
        "> are drawn with positioned text and ruling lines; the fenced block",
        "> below retains the original column alignment.",
        "",
        "```",
        *body,
        "```",
        "",
    ])


# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------

def main() -> None:
    raw = run_pdftotext()
    lines = strip_running_chrome(raw.splitlines())
    starts = find_section_starts(lines)
    starts.append(len(lines))

    OUT.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    skipped: list[Path] = []
    for sec, start, end in zip(SECTIONS, starts, starts[1:]):
        path = OUT / sec.path
        if sec.path in MANUAL_CURATION:
            skipped.append(path)
            continue
        body = lines[start + 1:end]  # skip the anchor line itself
        if sec.kind == "appendix":
            text = format_appendix(sec, body)
        else:
            text = format_prose(sec, body)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        written.append(path)

    print(f"Wrote {len(written)} files under {OUT}")
    for p in written:
        print(f"  {p.relative_to(OUT)}  ({p.stat().st_size:>6} bytes)")
    if skipped:
        print(f"\nSkipped {len(skipped)} hand-curated file(s):")
        for p in skipped:
            print(f"  {p.relative_to(OUT)}")


if __name__ == "__main__":
    main()
