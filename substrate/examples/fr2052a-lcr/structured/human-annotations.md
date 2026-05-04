# Human Visual Annotations

This file records human descriptions of visual content (diagrams, tables,
layouts) in the FR 2052a PDF that cannot be reliably reconstructed from
text-only extraction. Each entry is the source of truth for a corresponding
hand-curated passage in the Markdown output.

The pipeline rule:

- `pdftotext` produces the raw textual content.
- For pages that contain visual structure beyond linear prose, a human
  describes what is on the page in this file.
- The Markdown for those pages is hand-edited to reflect both the text and
  the description, and the file is added to the manual-curation list in
  `scripts/extract.py` so the splitter does not overwrite it on re-runs.

## Appendix I

### Diagram 1 — FR 2052a Tables and Information Hierarchy

**Visual layout (from human inspection of the PDF):**
Three boxes side by side, titled "Inflows", "Outflows", and "Supplemental".
Each box contains a vertical stack of smaller boxes, one per data table in
that category. "Comments" appears as a separate small box positioned with
the Supplemental column.

**Decision:** A two-dimensional table representation does not add value here
— the diagram conveys a one-to-many grouping. Render as a hierarchical
bullet list with the three categories at the top level and the data tables
nested beneath them.

### Table 2 — Example: data element aggregation

**Visual layout (from human inspection of the PDF):**
A table with 11 columns, one header row, and three body rows. The first
column header reads "O.W fields:" and its cells label each example row as
"Example 1", "Example 2", "Example 3". The remaining 10 column headers are
field names from the O.W (Outflows-Wholesale) data table.

**Column headers:** O.W fields:, Reporting Entity, Currency, Converted, PID,
Product, Maturity Amount, Maturity Bucket, Internal, Loss Absorbency,
Business Line.

**Body rows:**

| Example | Reporting Entity | Currency | Converted | PID | Product | Maturity Amount | Maturity Bucket | Internal | Loss Absorbency | Business Line |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Parent | USD | N | 11 | Unstructured Long Term Debt | 1,500 | > 4 years <= 5 years | N | TLAC | Corporate Treasury |
| 2 | Parent | GBP | N | 11 | Unstructured Long Term Debt | 2,000 | > 5 years | N | TLAC | Corporate Treasury |
| 3 | Parent | GBP | N | 11 | Unstructured Long Term Debt | 250 | > 1 year <= 2 years | N | TLAC | Corporate Treasury |

Note that example 1 reports 1,500 = 500 + 1,000 (the two USD-denominated
bonds are aggregated because they share a maturity bucket and all other
non-numeric fields).

**Note printed below the table in the PDF:**
"The Counterparty, G-SIB, Maturity Optionality, Collateral Class, Collateral
Value, Forward Start Amount, Forward Start Bucket, Internal Counterparty
fields are not required in these example records."

**Decision:** Render as a native Markdown table. 11 columns is wide but
readable. Replace the first column header with "Example" since that is what
the cells convey; record the original "O.W fields:" header in this
annotation file.

### Table 3 — Product Reference Syntax

**Visual layout (from human inspection of the PDF):**
A table with three columns ("Prefix", "Table", "Product #") and three body
rows. Two additional columns interspersed in the original layout contain
only dots for visual positioning; they carry no semantic content and are
ignored. The table illustrates how prefix + table letter + product number
combine to form a product reference code.

**Body rows (one per prefix):**

- I (Inflows) → tables: A (Assets), U (Unsecured), S (Secured), O (Other) → Product #: `#`
- O (Outflows) → tables: D (Deposits), W (Wholesale), S (Secured), O (Other) → Product #: `#`
- S (Supplemental) → tables: DC (Derivatives & Collateral), L (Liquidity Risk Measurement), B (Balance Sheet), I (Informational Items), FX (Foreign Exchange) → Product #: `#`

**Decision:** Render as a 3-column Markdown table. The Table column holds
multiple table identifiers per row; use `<br>` line breaks inside the cell
so each identifier appears on its own visual line.

### Table 4 — Example: required versus dependent fields

**Visual layout (from human inspection of the PDF):**
Same structural shape as Table 2, but for the I.A (Inflows-Assets) data
table and with a single example row. 12 columns: Reporting Entity, Currency,
Converted, PID, Product, Sub-Product, Market Value, Lendable Value, Maturity
Bucket, Collateral Class, Treasury Control, Accounting Designation.

**Single body row:**
Reporting Entity = Bank, Currency = USD, Converted = N, PID = 2, Product =
Capacity, Sub-Product = FHLB, Market Value = 150, Lendable Value = 100,
Maturity Bucket = > 5 years, Collateral Class = L-3, Treasury Control = Y,
Accounting Designation = Available for Sale.

**Note printed below the table in the PDF:**
"The Forward Start Amount, Forward Start Bucket, Effective Maturity Bucket,
Encumbrance Type, and Internal Counterparty fields are not required in this
example record."

**Decision:** Render as a native Markdown table with the 12 field columns.
No "Example" label column (Table 4 has only one example, so the label adds
no information).

### Data Tables (figure)

**Visual layout (from human inspection of the PDF):**
A composite figure depicting all 13 FR 2052a data tables. Each table is
drawn as a box with a header (the table name) and a body listing the table's
column names with the column type (text / numeric / percent) shown next to
each name. Columns are coloured: red = mandatory, blue = optional. The 13
boxes are grouped into the same three sections used in the document
structure — Inflows (4 boxes), Outflows (4 boxes), Supplemental (5 boxes) —
plus a separate Comments mechanism shown alongside the Supplemental column.

**Decision:** Render the structure now (one Markdown table per data table,
columns: Field, Type), grouped under three section headings. Defer the
red/blue mandatory-vs-optional encoding to Appendix II — that appendix is
the authoritative requirements specification and encodes the same
information at a finer (per-product) granularity, so reproducing the
per-table colours here would duplicate without adding precision.

**Caveat about types:** The type values (text / numeric / percent) come
from the raw text extraction of the figure. Because pdftotext infers
columns from x-coordinate positions, some types are misaligned by one or
two cells in the source extraction. They are transcribed verbatim below
and should be cross-checked against Field Definitions and Appendix II if
a precise typing is required for any specific field.

## Appendix II-a

### Product / Sub-Product Requirements table

**Visual layout (from human inspection of the PDF):**
A single logical table broken across two pages (the column header repeats
on the second page). Five header columns: Table, PID, Product, Sub-Product,
Sub-Product 2.

A row in the source is keyed by the Table column: each row may pair one
table name with one or more (PID, Product) entries, plus a list of allowed
Sub-Product values and an optional list of allowed Sub-Product 2 values.

**Why the raw text extraction is unusable here:** the text in this
appendix is rendered glyph-by-glyph (each character placed at an exact
x-coordinate), so pdftotext interprets the inter-character spacing as
inter-word spacing. The result reads as
`"Infl ows - As s ets ... Federa l Res erve Ba nk"` instead of
`"Inflows - Assets ... Federal Reserve Bank"`.

**Decision:** Render as a 4-column Markdown table:

1. **Table** — the source's Table column.
2. **PID & Product** — the source's PID and Product columns combined into
   a single cell. When a row pairs multiple (PID, Product) entries, list
   each as `PID — Product` on its own line within the cell.
3. **Sub-Product** — list of allowed values inside the cell.
4. **Sub-Product 2** — list of allowed values inside the cell, or empty
   if the row has none.

Use `<br>` for in-cell line breaks (same convention as Table 3 in
Appendix I).

**Extraction technique used here:** running `pdftotext` with `-layout`
preserves columns but exposes a font-rendering quirk in this appendix
where each glyph is positioned individually, producing output like
`"Federa l Res erve Ba nk"`. Switching to `pdftotext -raw` (which uses
content-stream order rather than coordinate-based reflow) sidesteps the
issue: the table comes out as one cell per line in row-major order. Then
`scripts/despace.py` collapses the stray inter-character spaces using a
heuristic that treats capitalised tokens as word starts and the lowercase
connectives `of` / `and` as standalone words. Together these two steps
produce the data verbatim.

**Reproduce:**

```bash
pdftotext -raw -enc UTF-8 -f 87 -l 88 raw/FR_2052a20250226_f.pdf - \
  | python structured/scripts/despace.py
```

**Rows extracted (9 total, table broken across pages 87 and 88):**

| # | Table | PID/Product | Sub-Product | Sub-Product 2 |
|---|---|---|---|---|
| 1 | Inflows - Assets | 2 — Capacity | 10 central banks + GSEs | — |
| 2 | Inflows - Assets | 3 — Unrestricted Reserve Balances; 4 — Restricted Reserve Balances | 8 central banks + Currency and Coin (9) | — |
| 3 | Inflows - Secured | 4 — Collateral Swaps | 5 collateral classes (Pledged) | — |
| 4 | Outflows - Secured | 4 — Collateral Swaps | 5 collateral classes (Received) | — |
| 5 | Outflows - Secured | 6 — Exceptional Central Bank Operations | 8 central banks + Covered FRB Facility Funding (9) | — |
| 6 | Outflows - Secured | 7 — Customer Shorts; 8 — Firm Shorts | 6 short/long settlement variants | — |
| 7 | Outflows - Secured | 9 — Synthetic Customer Shorts; 10 — Synthetic Firm Financing | 6 synthetic shorts variants | — |
| 8 | Inflows - Secured | 9 — Synthetic Customer Longs; 10 — Synthetic Firm Sourcing | 6 synthetic longs variants | — |
| 9 | Supplemental — Derivatives & Collateral | 10 PIDs (1–10) covering gross derivative values, settlements, initial/variation margin | 5 collateral states | 5 venue/agency types |

## Appendix II-b

### Counterparty Requirements table

**Visual layout (from human inspection of the PDF):**
A single logical table broken across three pages by page breaks, with the
header row repeating on each page. Five columns: Table, PID, Product,
Applicable Counterparty Values, Not Applicable Counterparty Values.

A row is keyed by a unique (Applicable, Not Applicable) configuration.
Each row may pair this configuration with one OR MORE (Table, PID,
Product) tuples. Some rows span many tables — e.g. one row groups
products from eight different tables, all sharing the same applicability.

Six rows total once the page breaks are merged:

- **Page 1** — 2 rows.
- **Page 2** — 3 rows.
- **Page 3** — 1 row.

**Decision:** Render as a 3-column Markdown table:

1. **Tables, PIDs & Products** — collapses the source's Table, PID, and
   Product columns into a single cell, presented as a hierarchical
   bullet list with the Table at the top level and `PID — Product`
   pairs nested under each Table. Use HTML `<ul>` / `<li>` because
   Markdown bullet syntax does not render reliably inside table cells.
2. **Applicable Counterparty Values** — `<br>`-separated list.
3. **Not Applicable Counterparty Values** — `<br>`-separated list, or
   `—` if the row has none.

The hierarchical first column makes the (Table, PID, Product) tuples'
structure obvious: a single PDF row that groups products from many
tables becomes one tall hierarchy instead of two parallel columns of
lists that the reader has to align mentally.

**Despace exception list expanded:** the original `EXCEPTIONS = {"of",
"and"}` was insufficient here — words like "Outstanding Draws on Unsecured
Revolving Facilities", "Investment Company or Advisor", "Cash Items in the
Process of Collection", and "Municipalities for VRDN Structures" appeared
correctly spaced in `pdftotext -raw` output but were collapsed by the
heuristic. Expanded to include common short connectives:
`{of, and, or, on, in, the, for, to, with, by, at}`. Single-letter
articles (`a`, `I`) are deliberately omitted because their token form
collides with mangled-word tails (e.g. "Federa l" would split wrongly).

**Reproduce:**

```bash
pdftotext -raw -enc UTF-8 -f 89 -l 91 raw/FR_2052a20250226_f.pdf - \
  | python structured/scripts/despace.py
```

**Counterparty value list (19 in total, source order):**

1. Retail
2. Small Business
3. Non-Financial Corporate
4. Sovereign
5. Central Bank
6. Government Sponsored Entity
7. Public Sector Entity
8. Multilateral Development Bank
9. Other Supranational
10. Pension Fund
11. Bank
12. Broker-Dealer
13. Investment Company or Advisor
14. Financial Market Utility
15. Other Supervised Non-Bank Financial Entity
16. Debt Issuing Special Purpose Entity
17. Non-Regulated Fund
18. Municipalities for VRDN Structures
19. Other

## Appendix II-c

### Collateral Class Requirements table

**Visual layout (from human inspection of the PDF):**
A simple matrix with five columns: PID, Product, Required, Dependent,
Not Applicable. Each row is one (PID, Product) tuple with exactly one
check mark, indicating which of the three categories applies. Rows are
grouped into sections by table (Inflows - Assets, Inflows - Unsecured,
…, Supplemental - Foreign Exchange) — the section name appears as an
inline header within the table rather than as a separate column. The
table is laid out across four pages of the source PDF; the markdown
output below is the merged single-table view.

**Why text-only extraction failed:** the check marks are Wingdings glyphs
(U+F0FC) drawn in absolute x-coordinate positions. `pdftotext -layout`
did emit them, but on each page the layout-mode column shifted by 5
characters relative to the previous page, and pdftotext occasionally
double-counted the glyph (showing a phantom check at the right edge of
the row). pdfplumber gives clean per-character access with absolute
coordinates and font names, which lets us pinpoint the column
unambiguously by checking which header label's bounding box the glyph's
x-coordinate falls under.

**Decision:** Render as a 5-column Markdown table with section names as
inline bolded separator rows. One row per (PID, Product), with `✓` in
exactly one of Required / Dependent / Not Applicable. The original PDF
splits the table across four pages; the Markdown file consolidates them.

**Reproduce:**

```bash
python structured/scripts/extract_iic.py
```

The script (`scripts/extract_iic.py`) is the appendix-specific
generator. It opens the PDF with pdfplumber, finds the column header
positions on each page, classifies every Wingdings glyph by its
x-coordinate against those header positions, and emits the merged
Markdown table.

**Coverage:** 148 product rows across 13 sections, matching the FR 2052a
data-table organisation in Appendix I.

## Appendix II-d

### Forward Start Exclusions

**Visual layout (from human inspection of the PDF):**
A simple list of (PID, Product) entries grouped by table, spanning three
pages of the source PDF. No additional columns — every entry in the list
shares the same status (excluded from forward-start fields). Two columns
in the source (PID, Product) under each table heading.

**Decision:** Render as a Markdown nested bullet list (table heading at
the top level, `PID — Product` entries nested beneath). A two-column
table would add visual weight without adding information.

**Source typo correction:** the source PDF labels the section containing
products `S.B.1`–`S.B.6` (Regulatory Capital Element, Other Liabilities,
Non-Performing Assets, Other Assets, Counterparty Netting, Carrying Value
Adjustment) as "Supplemental - Informational". This is incorrect — these
PIDs belong to the **Supplemental - Balance Sheet** table (`S.B.x`
prefix). The Markdown corrects the heading to "Supplemental - Balance
Sheet"; this annotation records the source-document discrepancy.

**Outflows - Deposits** is annotated in the source with the parenthetical
"(forward start fields not provided)" — a label clarifying that the
exclusion applies to the entire Outflows-Deposits table because forward
start fields are not supported there. Preserved in the rendered output.

**Reproduce:**

```bash
pdftotext -raw -enc UTF-8 -f 96 -l 98 raw/FR_2052a20250226_f.pdf - \
  | python structured/scripts/despace.py
```

**Despace exception list expanded again:** added `be`, `not`, `than` so
phrases like "Cannot be Transferred", "Greater than 30-days", and
"(forward start fields not provided)" survive. Also a structural fix to
the despace heuristic: when the prefix tokens before an exception look
like real words (any token ≥ 4 chars), they are emitted separately rather
than concatenated. This was needed for the descriptive-prose paragraph at
the top of II-a / II-d, where pdftotext's raw output is correctly spaced
but the previous heuristic would re-concatenate it.

## Appendix III

### Asset Category Table

**Visual layout (from human inspection of the PDF):**
Three tables across three pages of the source PDF, each with two columns
(Asset Category, Asset Category Description) and the same column header
row. The body rows are interleaved with section banner rows that span
both columns and label the group below them:

- Page 1 — three banners: "HQLA Level 1", "HQLA Level 2a", "HQLA Level 2b".
- Page 2 — one banner: "Non-HQLA Assets that do not meet the asset-specific
  tests detailed in section 20 of Regulation WW". The codes mirror the
  HQLA codes from page 1 minus the `-Q` suffix (i.e. they are the same
  asset descriptions but for the variants that fail the section-20 tests).
  No subgroup banners — the section is one flat list.
- Page 3 — one banner: "Non-HQLA Assets other". A single flat list of
  codes (S-8, CB-4, G-4, E-3..E-10, IG-3..IG-8, N-1..N-8, L-1..L-12,
  Y-1..Y-4, C-1, P-1..P-2, LC-1..LC-2, Z-1) with no subgrouping.

A short prose note above the first table explains the `-Q` suffix.

**Decision:** Render as a Markdown nested bullet list (group banner at
the top level, `Code — Description` entries nested beneath). Same
shape as Appendix II-d. The HQLA Level 1 / 2a / 2b banners are
top-level groups (rather than nesting them all under a parent "HQLA"
node) because the source treats them as peers of the two Non-HQLA
sections within a single asset-category-code namespace. The two
Non-HQLA banners are rendered as "Non-HQLA — Assets that do not
meet…" and "Non-HQLA — Other" to make their parallel role obvious.

**Source typo correction:** the source PDF spells "currrency" (three
r's) in the CB-2-Q and CB-2 descriptions ("…the home currrency of
the central bank"). Corrected to "currency" in the rendered output;
flagged with a Markdown footnote in the affected file.

**Intentional source asymmetries preserved:**

- S-5-Q, S-7-Q on page 1 carry "(excluding central banks)"; the
  corresponding non-Q codes S-5 and S-7 on page 2 omit the
  parenthetical. Preserved as-is.
- IG-2-Q reads "Investment grade municipal obligations"; IG-2 reads
  "Investment grade U.S. municipal general obligations". Preserved
  as-is.

**Reproduce:** No script — the auto-generated fenced output of
`extract.py` for this section is sufficient as the input; the file
above is hand-edited from that fenced block.

## Appendix IV-a

### Maturity Bucket Value List

**Visual layout (from human inspection of the PDF):**
A single page laying out the allowed Maturity Bucket values in two
side-by-side columns, read top-to-bottom column-major. The left column
runs `Open, Day 1, Day 2, …, Day 41`; the right column continues
`Day 42, …, Day 60, 61 - 67 Days, 68 - 74 Days, 75 - 82 Days,
83 - 90 Days, 91 - 120 Days, 121 - 150 Days, 151 - 179 Days,
180 - 270 Days, 271 - 364 Days, >= 1 Yr <= 2 Yr, >2 Yr <= 3 Yr,
>3 Yr <= 4 Yr, >4 Yr <= 5 Yr, >5 Yr, Perpetual`. The two-column layout
is purely a page-fitting concern and carries no semantic grouping.

**Decision:** Render as a single flat Markdown bullet list in the
source's intended order (left column then right column). The
typographic two-column split is dropped.

**Reproduce:** No script — manually transcribed from the fenced
auto-generated output of `extract.py`, then re-ordered into a single
column-major list.

## Appendix IV-b

### Maturity Bucket Tailoring

**Visual layout (from human inspection of the PDF):**
A nested numbered structure: top-level items `(1) … (3)` group firms by
regulatory category (Category I/II, Category III/IV with wSTWF > $50B,
Category IV with wSTWF < $50B), and second-level items `(a) … (d)` give
specific bucketing rules within each category. Each lettered item is
introduced by a paragraph of prose and followed by a small diagram that
visualises the maturity-bucket layout for that rule.

Each diagram is a horizontal strip with a row of column headers naming
the kinds of buckets (e.g. `Open`, `Daily`, `Weekly* Buckets`,
`30-Day Buckets`, `90-Day Buckets`, `Yearly Buckets`, `> 5 Years`,
`Perpetual`, or for some rules residual-maturity ranges instead). Below
the headers are two text rows: a day-range line (e.g. `Day 1 … Day 60`,
`Day 61 … Day 90`) and a bucket-count line (e.g. `60 buckets`,
`4 buckets`). The two text rows together describe the contents of each
header column. Visually they sit under a continuous ruled axis, but
semantically each column is independent.

A footnote at the very end of the appendix clarifies the weekly buckets:
*The first two "weekly" buckets contain 7 days, while the last two
contain 8 days (i.e., days 61-67, 68-74, 75-82, 83-90).*

**Decision:** Render each diagram as a Markdown table with one header
row (the bucket-kind labels) and one value row (the day-range and
bucket-count fused into a single cell, e.g. `Day 1 – Day 60, 60 buckets`).
For columns whose header alone is sufficient (`Open`, `Perpetual`, the
bare `> 5 Years` column in (1)(a)) the value cell is left empty.
The numbered structure is preserved as Markdown headings: `##` for the
top-level firm category and `###` for each lettered rule, with the
original prose used verbatim as the heading text. The weekly-buckets
footnote is rendered as a trailing note after a horizontal rule.

**Reproduce:** No script — manually transcribed from the fenced
auto-generated output of `extract.py`.

## Appendix VI

### LCR Formulas (pages 108–110)

**Why text extraction failed:** The formulas use Cambria/CambriaMath font
subsets (`SCLACN+Cambria`, `SZVSQN+CambriaMath`, `NAWWKX+Cambria-Italic`)
whose ToUnicode CMap is broken in two ways:

1. **Character doubling:** Each glyph maps to *two* copies of the same
   Unicode codepoint (e.g., one "L" glyph → U+1D43F U+1D43F = `𝐿𝐿`).
2. **Character conflation:** Multiple distinct glyphs (e.g., L, C, R)
   all map to the *same* codepoint. The font has only ~14 unique output
   characters (L, H, a, T, N, C, h, O, s, B, M, U, e, c) for what should
   be the full alphabet.

Additionally, `pdftotext` encodes the resulting (incorrect) Supplementary
Multilingual Plane codepoints as CESU-8 surrogate pairs (byte sequence
`ED XX XX ED XX XX`) rather than valid UTF-8, producing U+FFFD replacement
characters when read.

The character identity is irrecoverably lost in the PDF metadata. No text
extraction tool can recover the formulas.

**Page 110 — Maturity mismatch formulas:** These two formulas (Largest net
cumulative maturity outflow amount, Net day 30 cumulative maturity outflow
amount) are rendered entirely as graphical objects with no text layer at all.
`pdftotext` produces nothing for them. Transcribed from a screenshot saved at
[`screenshots/p110-maturity-mismatch-formulas.png`](screenshots/p110-maturity-mismatch-formulas.png).

**Decision:** Transcribe formulas from 12 CFR 249 (the LCR Rule) and the
Board's mapping document structure, matching the visible layout (operators,
coefficients, bracket structure) from the garbled but structurally intact
extraction. Page 110 formulas transcribed from screenshot. Render as a fenced
code block with plain-text math notation.

### Mapping Tables (pages 111–179)

The table pages use a repeating "Field / Value" structure for each numbered
LCR provision (140 total, numbered (1) through (140)). Each provision
references a section of the LCR Rule and specifies the FR 2052a field
constraints.

`pdfplumber.extract_text()` handles these cleanly — no font issues, no
layout problems. The only artifact is page-break blank lines splitting
multi-line values (counterparty lists spanning pages), which the formatter
joins automatically.

Page 111 contains a standalone "Outflow Adjustment Percentage" table
mapping firm categories to their percentage; this is hand-formatted.

**Reproduce:**

```bash
python structured/scripts/extract_vi.py
```

## Appendix VII

### STWF Mapping Tables (pages 180–194)

**Visual layout (from human inspection of the PDF):** Each numbered
sub-table uses a two-column "Field / Value" format identical to the
Appendix VI mapping tables. Items are grouped under section headings
("Item 1.a", "Item 1.b", etc.) with 24 total sub-tables numbered
(1) through (24). The document maps FR 2052a data identifiers to the
FR Y-15 Schedule G (STWF Indicator) line items.

No font issues; `pdfplumber.extract_text()` handles all pages cleanly.
The `pdftotext -layout` extraction interleaves columns from side-by-side
tables, which is why the fenced verbatim was unreadable.

**Decision:** Extract via `pdfplumber.extract_text()`, same approach as
Appendix VI mapping tables. Parse "Field Value" headers, known field
names (sorted by length to avoid prefix shadowing), and item/table
headings. Render as markdown heading hierarchy (`##` for Items, `###`
for sub-tables) with `| Field | Value |` tables. Multi-line cell values
joined with `<br>`.

**Reproduce:**

```bash
python structured/scripts/extract_vii.py
```

## Appendix VIII: NSFR to FR 2052a Mapping (pages 195–253)

### NSFR Formulas (pages 195–196)

Same broken Cambria/CambriaMath font as Appendix VI. The formulas use
Mathematical Italic characters (U+1D400 block) where each glyph is
doubled, and multiple different source glyphs map to the same codepoint.
Decoded output is garbled — letter identities are irrecoverable.

**Decision:** Transcribe from 12 CFR 249 §.100–§.109 (the NSFR Rule)
and the visible structure of the garbled extraction. The formulas define
the NSFR ratio, ASF amount, RSF amount, and derivatives RSF amount
components. Mapping table ID references (i_102, i_110, etc.) are
preserved as cross-references to the numbered provisions.

### Reference Key (page 195)

The NSFR reference key is more extensive than VI/VII. In addition to
`*`, `#`, and `NULL`, it defines compound terms:

- **Level 1 HQLA / Level 2A HQLA / Level 2B HQLA / HQLA**: specific
  Collateral Class value sets
- **Financial Sector Entity / Non-Financial Wholesale Entity**: specific
  Counterparty value sets

These are rendered as a Markdown table for machine readability.

### Rules of construction (§.102) — page 196

Prose section explaining how S.B.5 (Counterparty Netting) and S.B.6
(Carrying Value Adjustment) products adjust gross balances. Rendered as
native Markdown with bullet list.

### Mapping Tables (pages 197–253)

114 numbered NSFR provisions with "Field / Value" structure, same format
as VI and VII. `pdfplumber.extract_text()` handles these cleanly — no
font issues.

**Section structure:**
- ASF Amount Values: provisions (1)–(44), grouped by ASF factor
  percentage (100%, 95%, 90%, 50%, 0%)
- RSF Amount Values: provisions (45)–(101), grouped by RSF factor
  percentage (0%, 5%, 15%, 50%, 65%, 85%, 100%), plus encumbered assets
- Calculation of NSFR derivatives amounts (§.107): provisions (102)–(113)
- Rules for consolidation (§.109): provision (114)

**Additional fields not in VI/VII:** Collection Reference, Product
Reference, Sub-Product Reference, Sub-Product2, Collateral Level,
Netting Eligible.

**Footnotes:** 5 footnotes extracted inline as `[^N]` Markdown footnotes.
Footnote 2 explains the "less than" maturity bucket convention; footnote
3 clarifies the encumbered asset RSF section scope; footnotes 4 and 5
define "Overcollateralized" for variation margin received/pledged.

**Reproduce:**

```bash
python structured/scripts/extract_viii.py
```
