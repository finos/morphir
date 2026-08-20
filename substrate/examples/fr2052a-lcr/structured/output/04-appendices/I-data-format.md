# Appendix I: FR 2052a Data Format, Tables, and Fields

> This file is **hand-curated** with the help of human visual annotations
> recorded in [`../../human-annotations.md`](../../human-annotations.md).
> The splitter (`scripts/extract.py`) does not overwrite this file on re-run.
> Sections that have not yet been curated remain in fenced code blocks for
> later passes.

## Layout of the Data Collection

The technical architecture for the data collection of the FR 2052a report
subdivides the three general categories of inflows, outflows, and
supplemental items into 13 distinct data tables and includes a mechanism for
tracking comments, as displayed in the diagram below. These tables are
designed to stratify the assets, liabilities, and supplemental components of
a firm's liquidity risk profile based on common data structures, while still
maintaining a coherent framework for liquidity risk reporting.

### Diagram 1 — FR 2052a Tables and Information Hierarchy

The original diagram shows three side-by-side boxes ("Inflows", "Outflows",
"Supplemental"), each containing a vertical stack of smaller boxes — one per
data table in that category. "Comments" appears as a separate small box in
the Supplemental column.

- **Inflows**
  - Assets
  - Unsecured
  - Secured
  - Other inflows
- **Outflows**
  - Deposits
  - Wholesale
  - Secured
  - Other outflows
- **Supplemental**
  - Derivatives & Collateral
  - Liquidity Risk Measurement
  - Balance Sheet
  - Informational
  - Foreign exchange
  - Comments

## The FR 2052a Data Element

Each table is comprised of a set of fields (i.e., columns) that define the
requisite level of aggregation or granularity for each data element (i.e.,
row, or record).[^15] The FR 2052a framework is a "flat" or tabular
structure with predefined columns and an unconstrained number of rows. The
volume of data elements reported should therefore change dynamically as the
size and complexity of the reporting firm's funding profile changes.

[^15]: Appendix I details the structure of each table.

This instruction document uses the term *data element* to describe a unique
combination of non-numeric field values in a FR 2052a table, or in other
words, a unique record in one of the FR 2052a tables. Numeric values (e.g.,
contractual cash flow amounts, market values, lendable values, etc.) are
expected to be aggregated across the unique combinations of all other fields
in each FR 2052a table.

- All notional currency-denominated values should be reported in millions of
  that currency (e.g., U.S. dollar-denominated transactions in USD millions,
  sterling-denominated transactions in GBP millions, etc.)
- Example: The holding company has four outstanding issuances of plain
  vanilla long-term debt:
  - 500mm USD-denominated bond maturing in 4 years and 6 months,
  - 1,000mm USD-denominated bond maturing in 5 years,
  - 2,000mm GBP-denominated bond maturing in 10 years, and
  - 250mm GBP-denominated bond maturing in 1 year and 6 months.
- Assume the USD-denominated liabilities are issued in New York, while the
  GBP-denominated liabilities are issued in London, and all three issuances
  qualify as TLAC. In this case, the two USD-denominated bonds should be
  summed up and reported as a single FR 2052a data element, as they exhibit
  the same values in all non-numeric fields (note that although the
  maturities are different, they both fall within the ">4 years <=5 years"
  maturity bucket). The two GBP issuances, however, should not be
  aggregated, as they fall in separate and distinct maturity buckets
  (">1 year <= 2 years" versus "> 5 years"). Table 2 below illustrates how
  these three data elements should be reported in the FR 2052a O.W
  (Outflows-Wholesale) table.

### Table 2 — Example: data element aggregation

The original table's first column header in the PDF is "O.W fields:"; its
cells label each row as "Example 1/2/3". Renamed here to "Example" for
readability — see [`../../human-annotations.md`](../../human-annotations.md).

| Example | Reporting Entity | Currency | Converted | PID | Product | Maturity Amount | Maturity Bucket | Internal | Loss Absorbency | Business Line |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Parent | USD | N | 11 | Unstructured Long Term Debt | 1,500 | > 4 years <= 5 years | N | TLAC | Corporate Treasury |
| 2 | Parent | GBP | N | 11 | Unstructured Long Term Debt | 2,000 | > 5 years | N | TLAC | Corporate Treasury |
| 3 | Parent | GBP | N | 11 | Unstructured Long Term Debt | 250 | > 1 year <= 2 years | N | TLAC | Corporate Treasury |

> The Counterparty, G-SIB, Maturity Optionality, Collateral Class, Collateral
> Value, Forward Start Amount, Forward Start Bucket, and Internal
> Counterparty fields are not required in these example records.

- Note: additional examples are included in the field and product definition
  sections of this document to illustrate the standard for aggregating and
  reporting FR 2052a data.

## Naming conventions and field types

This document uses a standard syntax to refer to specific tables, fields and
products in the FR 2052a data hierarchy.

- **Prefixes** are the first component of the FR 2052a data reference
  syntax. There are three distinct prefixes: `I`, `O` and `S`, which
  correspond to the first letter of each specific section in the FR 2052a
  data hierarchy: Inflows, Outflows and Supplemental.
- **Tables** are referenced using the appropriate prefix, followed by the
  first letter of the table as described in Table 3 below (with the
  exceptions of derivatives & collateral and foreign exchange, which are
  referenced as "DC" and "FX", respectively).
  - Example: the "Assets" table, which relates to inflows, is referenced as
    `I.A`, while the "Deposits" table, which relates to outflows, is
    referenced as `O.D`.
- **Products** are referenced using the table syntax and the corresponding
  product number.
  - Note: The `[Product]` field designation is omitted to simplify the
    reference syntax. A number following the table designation always refers
    to the product number for that table.
    - Table 3 below depicts the table combinations for the product syntax
      structure.
    - Example: "Unencumbered Assets" (product #1) in the "Assets" table is
      referred to as `I.A.1`.

### Table 3 — Product Reference Syntax

A product reference code is composed of a prefix (one of `I`, `O`, `S`), a
table letter, and a product number.

| Prefix | Table | Product # |
|---|---|---|
| `I` (Inflows) | `A` (Assets)<br>`U` (Unsecured)<br>`S` (Secured)<br>`O` (Other) | `#` |
| `O` (Outflows) | `D` (Deposits)<br>`W` (Wholesale)<br>`S` (Secured)<br>`O` (Other) | `#` |
| `S` (Supplemental) | `DC` (Derivatives & Collateral)<br>`L` (Liquidity Risk Measurement)<br>`B` (Balance Sheet)<br>`I` (Informational Items)<br>`FX` (Foreign Exchange) | `#` |

## Field Types

The data fields in each FR 2052a table fall into two categories:

1. **Mandatory fields** (May vary for each product, colored red in Table 4
   below)
2. **Dependent fields** (colored blue in Table 4)
   - Required for certain transaction types.
     - Example: the `[Forward Start Bucket]` field is generally only
       required for forward starting transactions.
     - Example: the `[Internal Counterparty]` field is only required for
       intercompany transactions.
   - `[Sub-Product]` required for certain products.
     - Example: The "Capacity" product in the Assets table (`I.A.2`)
       requires a `[Sub-Product]` designation.
       - Table 4 below depicts a sample data element reporting FHLB capacity
         of $100mm against category L-3 collateral, with market value of
         $150mm and a residual maturity of > 5 years.
     - Refer to Appendix II for a full listing of product/sub-product
       combinations.

### Table 4 — Example: required versus dependent fields

A sample record for the I.A (Inflows-Assets) table reporting FHLB capacity
of $100mm against L-3 collateral with a market value of $150mm and residual
maturity greater than 5 years.

| Reporting Entity | Currency | Converted | PID | Product | Sub-Product | Market Value | Lendable Value | Maturity Bucket | Collateral Class | Treasury Control | Accounting Designation |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bank | USD | N | 2 | Capacity | FHLB | 150 | 100 | > 5 years | L-3 | Y | Available for Sale |

> The Forward Start Amount, Forward Start Bucket, Effective Maturity Bucket,
> Encumbrance Type, and Internal Counterparty fields are not required in
> this example record.

## Data Tables[^16]

The original figure depicts all 13 FR 2052a data tables, each as a box
listing its columns (field name + type), grouped into Inflows (4),
Outflows (4) and Supplemental (5), with the Comments mechanism shown
alongside Supplemental. In the original each column is also colour-coded —
red for mandatory, blue for optional.

The mandatory-vs-optional classification is **not reproduced here**. The
authoritative source for which fields are required is Appendix II, which
encodes the same information at the finer per-product granularity. Each
field's complete definition is in [Field Definitions](../02-field-definitions.md).

[^16]: Note that the Currency and Converted attributes are required for each
    value field in accordance with the Field Definitions. These fields have
    been omitted from this figure to simplify the illustration of the
    FR 2052a data structure.

> Field types below are transcribed from the source figure's text
> extraction. Because pdftotext infers column positions from coordinates,
> a small number of type values may be misaligned. Cross-check against
> Field Definitions / Appendix II when a precise typing is critical.

### Inflows

#### Assets (I.A)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Sub-Product | text | D |
| Market Value | numeric | M |
| Lendable Value | numeric | M |
| Maturity Bucket | text | M |
| Forward Start Amount | numeric | D |
| Forward Start Bucket | text | D |
| Collateral Class | text | M |
| Treasury Control | text | M |
| Accounting Designation | text | M |
| Effective Maturity Bucket | text | D |
| Encumbrance Type | text | D |
| Internal Counterparty | text | D |
| Business Line | text | M |

#### Unsecured (I.U)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Counterparty | text | D |
| G-SIB | text | D |
| Maturity Amount | numeric | M |
| Maturity Bucket | text | M |
| Maturity Optionality | text | D |
| Effective Maturity Bucket | text | D |
| Encumbrance Type | text | D |
| Forward Start Amount | numeric | D |
| Forward Start Bucket | text | D |
| Internal | text | M |
| Internal Counterparty | text | D |
| Risk Weight | percent | D |
| Business Line | text | M |

#### Secured (I.S)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Sub-Product | text | D |
| Maturity Amount | numeric | M |
| Maturity Bucket | text | M |
| Maturity Optionality | text | D |
| Effective Maturity Bucket | text | D |
| Encumbrance Type | text | D |
| Forward Start Amount | numeric | D |
| Forward Start Bucket | text | D |
| Collateral Class | text | M |
| Collateral Value | numeric | M |
| Unencumbered | text | M |
| Treasury Control | text | M |
| Internal | text | M |
| Internal Counterparty | text | D |
| Risk Weight | percent | M |
| Business Line | text | M |
| Settlement | text | M |
| Counterparty | text | M |
| G-SIB | text | D |

#### Other (I.O)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Maturity Amount | numeric | M |
| Maturity Bucket | text | M |
| Forward Start Amount | numeric | D |
| Forward Start Bucket | text | D |
| Collateral Class | text | D |
| Collateral Value | numeric | D |
| Treasury Control | text | M |
| Counterparty | text | D |
| G-SIB | text | D |
| Internal | text | M |
| Internal Counterparty | text | D |
| Business Line | text | M |

### Outflows

#### Deposits (O.D)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Counterparty | text | M |
| G-SIB | text | D |
| Maturity Amount | numeric | M |
| Maturity Bucket | text | M |
| Maturity Optionality | text | D |
| Collateral Class | text | D |
| Collateral Value | numeric | D |
| Insured | text | M |
| Trigger | text | M |
| Rehypothecated | text | D |
| Business Line | text | M |
| Internal | text | M |
| Internal Counterparty | text | D |

#### Wholesale (O.W)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Counterparty | text | D |
| G-SIB | text | D |
| Maturity Amount | numeric | M |
| Maturity Bucket | text | M |
| Maturity Optionality | text | D |
| Collateral Class | text | D |
| Collateral Value | numeric | D |
| Forward Start Amount | numeric | D |
| Forward Start Bucket | text | D |
| Internal | text | M |
| Internal Counterparty | text | D |
| Loss Absorbency | text | D |
| Business Line | text | M |

#### Secured (O.S)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Sub-Product | text | D |
| Maturity Amount | numeric | M |
| Maturity Bucket | text | M |
| Maturity Optionality | text | D |
| Forward Start Amount | numeric | D |
| Forward Start Bucket | text | D |
| Collateral Class | text | M |
| Collateral Value | numeric | M |
| Treasury Control | text | M |
| Internal | text | M |
| Internal Counterparty | text | D |
| Business Line | text | M |
| Settlement | text | M |
| Rehypothecated | text | M |
| Counterparty | text | M |
| G-SIB | text | D |

#### Other (O.O)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Counterparty | text | D |
| G-SIB | text | D |
| Maturity Amount | numeric | M |
| Maturity Bucket | text | M |
| Forward Start Amount | numeric | D |
| Forward Start Bucket | text | D |
| Collateral Class | text | D |
| Collateral Value | numeric | D |
| Internal | text | M |
| Internal Counterparty | text | D |
| Business Line | text | M |

### Supplemental

#### Informational (S.I)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Market Value | numeric | M |
| Collateral Class | text | D |
| Internal | text | M |
| Internal Counterparty | text | D |
| Business Line | text | M |

#### Derivatives & Collateral (S.DC)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Sub-Product | text | D |
| Sub-Product 2 | text | D |
| Market Value | numeric | M |
| Collateral Class | text | D |
| Collateral Level | text | D |
| Counterparty | text | D |
| G-SIB | text | D |
| Effective Maturity Bucket | text | D |
| Encumbrance Type | text | D |
| Netting Eligible | text | D |
| Treasury Control | text | D |
| Internal | text | M |
| Internal Counterparty | text | D |
| Business Line | text | M |

#### Liquidity Risk Measurement (S.L)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Market Value | numeric | M |
| Collateral Class | text | D |
| Internal | text | M |
| Internal Counterparty | text | D |

#### Balance Sheet (S.B)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Collection Reference | text | D |
| Product | text | M |
| Product Reference | text | D |
| Sub-Product Reference | text | D |
| Collateral Class | text | D |
| Maturity Bucket | text | M |
| Effective Maturity Bucket | text | D |
| Encumbrance Type | text | D |
| Market Value | numeric | D |
| Maturity Amount | numeric | D |
| Collateral Value | numeric | D |
| Counterparty | text | D |
| G-SIB | text | D |
| Risk Weight | percent | D |
| Internal | text | M |
| Internal Counterparty | text | D |

#### Foreign Exchange (S.FX)

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Product | text | M |
| Maturity Amount Currency 1 | numeric | M |
| Maturity Amount Currency 2 | numeric | M |
| Maturity Bucket | text | M |
| Foreign Exchange Option Direction | text | D |
| Forward Start Amount Currency 1 | numeric | D |
| Forward Start Amount Currency 2 | numeric | D |
| Forward Start Bucket | text | D |
| Counterparty | text | M |
| G-SIB | text | D |
| Settlement | text | M |
| Business Line | text | M |
| Internal | text | M |
| Internal Counterparty | text | D |

### Comments

The Comments mechanism is shown adjacent to the Supplemental section in the
source figure but is not one of the 13 data tables; it captures
free-text annotations associated with reported records.

| Field | Type | Mandatory / Dependent |
|---|---|---|
| Reporting Entity | text | M |
| Collection | text | M |
| Product | text | M |
| Sub-Product | text | D |
| Comments | text | M |
