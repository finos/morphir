# FR 2052a PDF → Markdown Extraction

This folder contains the FR 2052a Complex Institution Liquidity Monitoring
Report instructions, extracted from the source PDF and split into a set of
Markdown files that mirror the document's original section structure.

The Markdown here is **not yet the substrate knowledge corpus**. It is a
faithful reformatting of the source document, intended as the input for a
later restructuring pass.

## Source

- `../raw/FR_2052a20250226_f.pdf` — FR 2052a Instructions, dated 2025-02-26
  (revision approved through Feb 2028). 106 pages of instructions plus
  three appended mapping documents (Appendices VI, VII, VIII) with their
  own page numbering.

## Status — where we are right now

| Section                                            | State                |
| -------------------------------------------------- | -------------------- |
| 01 General Instructions                            | ✅ auto-generated    |
| 02 Field Definitions                               | ✅ auto-generated    |
| 03 Product Definitions (all 13 group files)        | ✅ auto-generated    |
| Appendix I — Data Format, Tables, and Fields       | ✅ hand-curated      |
| Appendix II-a — Product/Sub-Product Requirements   | ✅ hand-curated      |
| Appendix II-b — Counterparty Requirements          | ✅ hand-curated      |
| Appendix II-c — Collateral Class Requirements      | ✅ hand-curated      |
| Appendix II-d — Forward Start Exclusions           | ✅ hand-curated      |
| Appendix III — Asset Category Table                | ✅ hand-curated      |
| Appendix IV-a — Maturity Bucket Value List         | ✅ hand-curated      |
| Appendix IV-b — Maturity Bucket Tailoring          | ✅ hand-curated      |
| Appendix V — Double Counting of Certain Exposures  | ✅ hand-curated (fenced verbatim; trailing VI/VII/VIII pointers removed) |
| Appendix VI — LCR to FR 2052a Mapping              | ✅ hand-curated      |
| Appendix VII — STWF to FR 2052a Mapping            | ✅ hand-curated      |
| Appendix VIII — NSFR to FR 2052a Mapping           | ✅ hand-curated      |

All product / appendix sections are now curated. Appendix V
is kept as fenced verbatim (prose-heavy, no tabular data); the only
hand edit was stripping the trailing pointers to Appendices VI/VII/VIII,
which live in their own files. Appendices VI and VIII required special
handling because the LCR/NSFR formulas use Cambria Math font subsets
with a broken ToUnicode CMap; formulas were transcribed from 12 CFR 249
and the visible document structure. The mapping tables (140 provisions
in VI, 114 provisions in VIII) were extracted via
`pdfplumber.extract_text()`.

## Why this approach

The source PDF is born-digital — text is stored as real Unicode, not
pixels — so OCR is unnecessary. Heading conventions in the document are
regular, which makes a deterministic splitter feasible for the bulk of
the content. We chose this over an ML extractor (Docling, Marker) for
three reasons:

1. **Reproducibility.** No model weights, no nondeterminism. The same
   PDF produces byte-identical Markdown for the auto-generated portions.
2. **Transparency.** Every transformation is visible in
   [`scripts/extract.py`](scripts/extract.py). When something looks
   wrong in the output we can trace it to a specific rule.
3. **Footprint.** `pdftotext` plus a few hundred lines of Python beats a
   multi-GB model download for a document this regular.

For the appendix tables, where positional graphics matter (check-mark
columns, cross-page table merging, custom-positioned glyphs), we drop
into per-appendix curation backed by `pdfplumber`. See *Curation
workflow* below.

## Pipeline

```
raw/FR_2052a20250226_f.pdf
  │
  │  ── extract.py ───────────────────────────────────────────────────────
  │  pdftotext -layout -enc UTF-8                       (column alignment)
  │       ▼
  │  structured/scripts/_full.txt                       (intermediate)
  │       ▼
  │  strip page chrome, locate section anchors,
  │  slice into per-section bodies, format prose / fenced appendices
  │       ▼
  │  structured/output/**/*.md                          (auto-generated files)
  │  (skipped if listed in MANUAL_CURATION)
  │
  │  ── per-appendix curation (where the auto output isn't enough) ──────
  │  pdftotext -raw OR pdfplumber                       (recovers structure)
  │       ▼
  │  scripts/despace.py                                 (de-glyph-spacing)
  │       ▼
  │  hand-edit, guided by structured/human-annotations.md
  │       ▼
  │  structured/output/04-appendices/*.md               (curated overwrites)
```

## Output layout

```
output/
  01-general-instructions.md
  02-field-definitions.md                       (one ## per field term)
  03-product-definitions/
    00-overview.md
    I.A-inflows-assets.md                       (one ### per product)
    I.U-inflows-unsecured.md
    I.S-inflows-secured.md
    I.O-inflows-other.md
    O.W-outflows-wholesale.md
    O.S-outflows-secured.md
    O.D-outflows-deposits.md
    O.O-outflows-other.md
    S.DC-supplemental-derivatives-collateral.md
    S.L-supplemental-lrm.md
    S.B-supplemental-balance-sheet.md
    S.I-supplemental-informational.md
    S.FX-supplemental-foreign-exchange.md
  04-appendices/
    I-data-format.md                            (curated — bullet list, MD tables)
    II-a-product-subproduct-requirements.md     (curated — 4-col MD table)
    II-b-counterparty-requirements.md           (curated — 3-col MD table, HTML <ul> in cells)
    II-c-collateral-class-requirements.md       (curated — 5-col MD table, generated)
    II-d-forward-start-exclusions.md            (curated — nested bullet list)
    III-asset-category-table.md                 (curated — nested bullet list)
    IV-a-maturity-bucket-value-list.md          (curated — flat bullet list)
    IV-b-maturity-bucket-tailoring.md           (curated — one MD table per rule)
    V-double-counting.md                        (curated — fenced verbatim, VI/VII/VIII tail removed)
    VI-lcr-mapping.md                           (curated — formulas + field/value tables)
    VII-stwf-mapping.md                         (curated — field/value tables)
    VIII-nsfr-mapping.md                        (curated — formulas + field/value tables)
```

Granularity is **one file per product group** (e.g. all `I.A.x` products
in one file), not one file per individual product. Per-product splitting
can be done as a follow-up if the corpus restructuring needs it.

## Prerequisites

- `pdftotext` (poppler / xpdf). Verified with version 4.00.
- Python 3.10+.
- `pdfplumber` (`pip install pdfplumber`). Required for `extract_iic.py`
  and any future curation that needs character-level coordinates or
  graphical-object access. Verified with version 0.11.9.

## How to reproduce

From the `examples/fr2052a-lcr` directory:

```bash
python structured/scripts/extract.py
```

The script is idempotent — it overwrites the contents of `output/` on
every run **except** files listed in the `MANUAL_CURATION` set inside
`extract.py`, which are left alone. The intermediate text dump is left
at `structured/scripts/_full.txt` for debugging; it is not part of the
published corpus and is safe to delete.

## What `extract.py` does (auto-generated content)

1. **Run pdftotext** with `-layout` (preserves table column alignment
   via fixed-width spacing) and `-enc UTF-8` (correctly emits bullet
   `•`, curly quotes, etc.).

2. **Strip running chrome.** The page header `FR 2052a Instructions`
   and the footer `Page X of 106` are removed. Three or more
   consecutive blank lines collapse to two.

3. **Locate section anchors.** A fixed list (`SECTIONS` in the script)
   names each top-level section in document order. The splitter walks
   the cleaned text and finds each anchor as the **first occurrence
   after the previous match** — this avoids false positives in the ToC
   at the top of the document. Unicode dash variants (`‐`, `–`, `—`)
   are normalised to ASCII hyphen so that `Short-Term` matches the
   source's `Short‐Term`.

4. **Format each section.**
   - Prose sections get a `#` H1 from the section title. Known
     sub-terms (the field-definition list, the General Instructions
     sub-headings, and `I.A.1` / `O.O.5` / etc. product IDs) are
     promoted to `##` or `###`. Bullet lines (`•`) become Markdown
     `-` lists; continuation lines fold into the same bullet.
   - Appendix sections are wrapped in fenced code blocks to preserve
     column alignment exactly. The hand-curation pass replaces them
     in the output, file by file.

A real product heading is distinguished from an inline reference (e.g.
"…reported under product I.A.2: Capacity. Exclude…") by requiring the
preceding line to be blank, the captured name to be ≤ 80 characters,
and the name to contain no mid-sentence `". "` punctuation.

## Curation workflow (per appendix)

This is the recipe used for Appendix I and II-a/b/c/d. Use the same
shape for III, IV-a, and IV-b.

1. **Look at the auto-generated fenced output** in
   `output/04-appendices/<appendix>.md` to gauge what the raw
   extraction looks like.
2. **Choose an extraction technique** based on what the appendix
   contains:
   - Pure prose / simple tables → `pdftotext -raw -enc UTF-8 -f N -l M
     | python scripts/despace.py`. Raw mode emits one cell per line in
     content-stream order, sidestepping pdftotext's coordinate-based
     reflow problems. `despace.py` collapses the per-glyph spacing that
     some appendices (II-a, II-b) use.
   - Tables with check-mark columns or other graphical encodings →
     pdfplumber. See `scripts/extract_iic.py` for a worked example
     that classifies Wingdings glyphs by header-column x-coordinate.
3. **Get a human description of the visual layout.** Capture it in
   [`human-annotations.md`](human-annotations.md) under a section
   for that appendix. Include: column shape, row keying, special
   structures (page breaks, multi-row cells), and the rendering
   decision you took (table vs nested list, column merging, etc.).
4. **Hand-edit** `output/04-appendices/<appendix>.md`:
   - Replace the original `> Preserved verbatim…` blockquote with a
     pointer to `human-annotations.md` and a `**hand-curated**` note.
   - Render the content as native Markdown.
5. **Add the file path to `MANUAL_CURATION`** in
   [`scripts/extract.py`](scripts/extract.py) so the splitter doesn't
   overwrite it on the next run.
6. **Run `python structured/scripts/extract.py`** and confirm the
   "Skipped N hand-curated file(s)" output mentions the new file.

### Conventions

- **PID / Product joining:** in compound cells, render as `PID — Product`
  (em-dash separator).
- **Hierarchical lists inside table cells:** use HTML `<ul>` / `<li>`
  rather than Markdown bullets. Markdown bullet syntax doesn't render
  reliably inside `|`-delimited cells across all renderers.
- **In-cell line breaks:** use `<br>` (works in GFM, VS Code,
  Docusaurus, and most other renderers).
- **Section names inside a table:** when the original groups rows by
  table name, render the table name as a bolded "section header row"
  (`| **Inflows - Assets** | | | |`) above the products.
- **Source typos:** correct them in the output and document the
  discrepancy in `human-annotations.md` with a Markdown footnote in
  the affected file pointing back.

## Scripts

```
structured/scripts/
  extract.py        # Top-level splitter. Manages the auto/manual mix
                    # via the MANUAL_CURATION set. Idempotent.
  despace.py        # Heuristic to collapse per-glyph spacing in
                    # raw-mode pdftotext output. Accepts a --range
                    # to slice the intermediate text. Iterates over
                    # tokens, treating capitalised tokens as word
                    # starts and a list of lowercase connectives
                    # (`of and or on in the for to with by at be
                    # not than`) as standalone words. Mangled-word
                    # fragments (≤ 3 char lowercase tokens) glue
                    # onto the preceding capital word; longer
                    # tokens are emitted standalone.
  extract_iic.py    # Appendix-specific generator for II-c using
                    # pdfplumber. Reads each page's header to find
                    # column x-positions, classifies every Wingdings
                    # check mark by column, emits a 5-column MD
                    # table with section headings as inline rows.
  extract_vi.py     # Appendix VI generator. Formulas transcribed
                    # from 12 CFR 249 (broken font in source PDF);
                    # mapping tables (140 provisions, pages 112-179)
                    # extracted via pdfplumber.extract_text().
  extract_vii.py    # Appendix VII generator. STWF mapping tables
                    # (24 sub-tables, pages 180-194) extracted via
                    # pdfplumber.extract_text().
  extract_viii.py   # Appendix VIII generator. NSFR formulas
                    # transcribed from 12 CFR 249 §.100-§.109
                    # (same broken font as VI); mapping tables
                    # (114 provisions, pages 197-253) extracted
                    # via pdfplumber.extract_text().
  _full.txt         # Cached pdftotext output. Regenerated on each
                    # extract.py run; safe to delete.
```

## Reproduce commands cheat-sheet

```bash
# Full re-run (auto + skipped curated files)
python structured/scripts/extract.py

# Despace a page range from the cached intermediate text
python structured/scripts/despace.py structured/scripts/_full.txt --range 3486 3582

# Despace a fresh pdftotext-raw extraction
pdftotext -raw -enc UTF-8 -f 87 -l 88 raw/FR_2052a20250226_f.pdf - \
  | python structured/scripts/despace.py

# Re-generate Appendix II-c from the PDF
python structured/scripts/extract_iic.py

# Re-generate Appendix VI from the PDF
python structured/scripts/extract_vi.py

# Re-generate Appendix VII from the PDF
python structured/scripts/extract_vii.py

# Re-generate Appendix VIII from the PDF
python structured/scripts/extract_viii.py
```

## Picking up the curation work in a fresh session

If you (or another assistant) want to continue from where we stopped:

1. **Read this file first**, then `human-annotations.md`. Together they
   describe the entire pipeline, the curation conventions, every
   decision made for the already-curated appendices, and the despace
   heuristic's rules.
2. **Check `MANUAL_CURATION` in `extract.py`** for the canonical list
   of curated files.
3. **Run `python structured/scripts/extract.py`** to confirm the
   environment works. The "Skipped N hand-curated file(s)" tail
   should mention 12 files (Appendix I, II-a/b/c/d, III, IV-a, IV-b,
   V, VI, VII, and VIII).
4. All appendices are now curated. No remaining extraction work.

## Known limitations

- **Footnote markers are inlined** in auto-generated prose. Footnote
  numbers appear as bare digits attached to words (e.g. `Pound
  Sterling (GBP); Japanese Yen (JPY).7`). No effort has been made to
  convert these to Markdown footnote syntax in the auto pipeline; the
  curated appendices use proper `[^N]` footnotes where helpful.
- **Bulleted-term descriptions are flattened** in auto-generated
  prose. Many bullets in Field Definitions use a "term on one line,
  description indented below" pattern; the splitter folds these into
  a single bullet line.
- **Math in the LCR enclosure (Appendix VI).** The LCR formula uses
  Mathematical Alphanumeric Symbols (U+1D400 block). Content is
  preserved; visual fidelity is not.
- **The front-matter cover page and ToC are not extracted.** The
  Markdown file structure of `output/` already encodes the same
  navigation that the ToC provides.

## Next steps (post-extraction)

The output here is the raw substrate — faithful to the source,
structured enough to navigate, but not yet a knowledge corpus. The
eventual transform into a substrate knowledge corpus is a separate
task and lives outside this folder.
