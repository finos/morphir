# Appendix VI: LCR to FR 2052a Mapping

> **Hand-curated.** The LCR formulas on pages 108–110 of the source PDF
> use Cambria Math font subsets with a broken ToUnicode CMap (each glyph
> maps to a doubled, incorrect math-italic codepoint). Formula text was
> transcribed from 12 CFR 249 and the visible document structure.
> The maturity-mismatch formulas on page 110 are purely graphical (no
> extractable text); they were transcribed from a screenshot
> ([`screenshots/p110-maturity-mismatch-formulas.png`](../../screenshots/p110-maturity-mismatch-formulas.png)).
> See [`human-annotations.md`](../../human-annotations.md) for details.
>
> Mapping tables (pages 111–179) extracted via `pdfplumber.extract_text()`.

Staff of the Board of Governors of the Federal Reserve System (Board) has developed this document to assist reporting firms subject to the liquidity coverage ratio rule (LCR Rule[^1]) in mapping the provisions of the LCR Rule to the unique data identifiers reported on FR 2052a. This mapping document is not a part of the LCR Rule nor a component of the FR 2052a report. Firms may use this mapping document solely at their discretion. From time to time, to ensure accuracy, an updated mapping document may be published and reporting firms will be notified of these changes.

## Key

| Symbol | Meaning |
|--------|---------|
| `*` | Values relevant to the LCR |
| `#` | Values not relevant to the LCR |
| `NULL` | Should not have an associated value |

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

Largest net cumulative maturity outflow amount
    = MAX [
        SUM(n=1 to m) [
            (Outflow values corresponding to .32(g), (h)(1), (h)(2),
                (h)(5), (j), (k), and (l) with maturity bucket of n
                * Respective outflow rates)
            - (Inflow values corresponding to .33(c), (d), (e), and (f)
                with maturity bucket of n * Respective inflow rates)
        ]
        ∀ m ∈ {1, 2, …, 30}
    ]

Net day 30 cumulative maturity outflow amount
    = SUM(n=1 to 30) [
        (Outflow values corresponding to .32(g), (h)(1), (h)(2),
            (h)(5), (j), (k), and (l) with maturity bucket of n
            * Respective outflow rates)
        - (Inflow values corresponding to .33(c), (d), (e), and (f)
            with maturity bucket of n * Respective inflow rates)
    ]
```

[^1]: Refer to LCR Rule as defined as specified in section 10(c) of the LRM standards.
[^2]: For the maturity mismatch add-on, please note that Open maturity should still be reported in FR 2052a, and the LCR calculation will convert Open to day 1 pursuant to section 31(a)(4) of the LCR Rule.

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


## HQLA Amount Values


## HQLA Additive Values


### (1) High-Quality Liquid Assets (Subpart C, §.20-.22)

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.A.1, 2, and 3 |
| Product | Matches PID |
| Sub‐Product | Not Currency and Coin |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | Open for I.A.3, # otherwise |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | HQLA (except A‐0‐Q for I.A.2) |
| Treasury Control | Y |
| Accounting Designation | # |
| Encumbrance Type | NULL |
| Internal Counterparty | # |

### (2) Rehypothecatable Collateral (Subpart C, §.20-.22)

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 4, 5, and 6 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | # |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | HQLA securities (not A‐0‐Q) |
| Collateral Value | * |
| Unencumbered | Y |
| Treasury Control | Y |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (3) Rehypothecatable Collateral (Subpart C, §.20-.22)

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.DC. 7 and 10 |
| Product | Matches PID |
| Sub‐Product | Rehypothecatable ‐ Unencumbered |
| Treasury Control | Y |
| Sub‐Product | 2 # |
| Market Value | * |
| Collateral Class | HQLA securities (not A‐0‐Q) |
| Collateral Level | # |
| Counterparty | # |
| G‐SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

## HQLA Subtractive Values


### (4) Excluded Sub HQLA (§.22(b)(3)and(4))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.L.1 |
| Product | Matches PID |
| Market Value | * |
| Collateral Class | HQLA |
| Internal | # |
| Internal Counterparty | # |

### (5) Early Hedge Termination Outflows (§.22(a)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.L.3 |
| Product | Matches PID |
| Market Value | * |
| Collateral Class | HQLA |
| Internal | # |
| Internal Counterparty | # |

### (6) Excess Collateral (§.22(b)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.DC.15 |
| Product | Matches PID |
| Sub‐Product | # |
| Treasury Control | Y |
| SID2 | # |
| Sub‐Product | 2 # |
| Market Value | * |
| Collateral Class | HQLA |
| Collateral Level | # |
| Counterparty | # |
| G‐SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # Unwind Transactions |

### (7) Secured Lending Unwind (Subpart C, §.21)

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, and 6 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days, but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | HQLA |
| Collateral Value | * |
| Unencumbered | Y if Effective Maturity Bucket is NULL, otherwise # |
| Treasury Control | Y |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (8) Secured Funding Unwind (Subpart C, §.21)

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3, 5, 6, 7 and 11 |
| Product | Matches PID SID Matches Sub‐Product |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or Unsettled (Forward), # otherwise |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | HQLA |
| Collateral Value | * |
| Treasury Control | Y |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | # |
| G‐SIB | # |

### (9) Asset Exchange Unwind (Subpart C, §.21)

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | # |
| Sub‐Product | Level 1 HQLA, Level 2A HQLA, and Level 2B HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days, not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | HQLA |
| Collateral Value | * |
| Unencumbered | Y if Effective Maturity Bucket is NULL, otherwise # |
| Treasury Control | Y |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

## OUTFLOW VALUES


### (10) Stable Retail Deposits (§.32(a)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.1 and 2 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (11) Other Retail Deposits (§.32(a)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.1, 2, and 3 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | Not FDIC for PID = 1 and 2, and # for PID = 3 |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (12) Insured Placed Retail Deposits (§.32(a)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.14 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (13) Non-Insured Placed Retail Deposits (§.32(a)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.14 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | Not FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (14) Other Retail Funding (§.32(a)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.15 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (15) Other Retail Funding (§.32(a)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.22 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (16) Other Retail Funding (§.32(a)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or Unsettled (Forward), # otherwise |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Retail or Small Business |
| G‐SIB | # |

### (17) Other Retail Funding (§.32(a)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.W.18 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (18) Structured Transaction Outflow Amount (§.32(b))
(The total amount for 32(b) is the relevant commitment amounts plus the incremental increase
from O.O.21)

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.21 (adds the incremental amount) |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (19) Net Derivatives Cash Outflow Amount (§.32(c))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.20 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≤ 30 calendar days |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (20) Mortgage Commitment Outflow Amount (§.32(d))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.6 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (21) Affiliated DI Commitments (§.32(e)(1)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm that is a depository institution |
| PID | O.O.4 and 5 |
| Product | Matches PID |
| Counterparty | Bank |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | *3 |
| Collateral Value | *4 3 For the purpose of all tables mapped to commitment outflow amounts in section .32(e), the Collateral Class field should be used to identify commitment exposures that are secured by Level 1 or Level 2A HQLA, in accordance with sections .32(e)(2) and (3). 4 For the purpose of all tables mapped to commitment outflow amounts in section .32(e), the Collateral Value field should be used to identify the amount of Level 1 or Level 2A HQLA securing the commitment exposure in accordance with sections .32(e)(2) and (3). |
| Internal | Y |
| Internal Counterparty | Bank from the U.S. subject to the LCR |
| Business Line | # |

### (22) Retail Commitments (§.32(e)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.4, 5 and 18 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days for O.O.4, O.O.5; # for O.O.18 |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | * |
| Collateral Value | * |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (23) Non-Financial Corporate Credit Facilities (§.32(e)(1)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.4 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank, GSE, PSE, MDB, Other Supranational |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | * |
| Collateral Value | * |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (24) Non-Financial Corporate Liquidity Facilities (§.32(e)(1)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.5 and 18 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank, GSE, PSE, MDB, Other Supranational, Municipalities for VRDN Structures |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days for O.O.5; # for O.O.18 |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | * |
| Collateral Value | * |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (25) Bank Commitments (§.32(e)(1)(v))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.4, 5 and 18 |
| Product | Matches PID |
| Counterparty | Bank |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days for O.O.4, O.O.5; # for O.O.18 |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | * |
| Collateral Value | * |
| Internal | Y |
| Internal Counterparty | Bank not from the U.S. or Bank from the U.S. not subject to the LCR |
| Business Line | # |

### (26) Bank Commitments (§.32(e)(1)(v))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.4, 5 and 18 |
| Product | Matches PID |
| Counterparty | Bank |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days for O.O.4, O.O.5; # for O.O.18 |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | * |
| Collateral Value | * |
| Internal | N |
| Internal Counterparty | NULL |
| Business Line | # |

### (27) Non-Bank and Non-SPE Financial Sector Entity Credit Facilities (§.32(e)(1)(vi))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.4 |
| Product | Matches PID |
| Counterparty | Pension Fund, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | * |
| Collateral Value | * |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (28) Non-Bank and Non-SPE Financial Sector Entity Liquidity Facilities (§.32(e)(1)(vii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.5 and 18 |
| Product | Matches PID |
| Counterparty | Pension Fund, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days for O.O.5; # for O.O.18 |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | * |
| Collateral Value | * |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (29) Debt Issuing SPE Commitments (§.32(e)(1)(viii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.4, 5 and 18 |
| Product | Matches PID |
| Counterparty | Debt Issuing SPE |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days for O.O.4, O.O.5; # for O.O.18 |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | * |
| Collateral Value | * |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (30) Other Commitments (§.32(e)(1)(ix))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.4, 5 and 18 |
| Product | Matches PID |
| Counterparty | Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days for O.O.4, O.O.5; # for O.O.18 |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | * |
| Collateral Value | * |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (31) Changes in Financial Condition (§.32(f)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.16 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (32) Changes in Financial Condition (§.32(f)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.12 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (33) Derivative Collateral Potential Valuation Changes (§.32(f)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.DC.5, 6, 8, and 9 |
| Product | Matches PID |
| Sub‐Product | # |
| Sub‐Product | 2 Not OTC – Centralized (Agent) or Exchange‐ traded (Agent) |
| Market Value | * |
| Collateral Class | Not level 1 HQLA |
| Collateral Level | # |
| Counterparty | # |
| G‐SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (34) Potential Derivative Valuation Changes (§.32(f)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.8 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (35) Collateral Deliverables (§.32(f)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.DC.15 |
| Product | Matches PID |
| Sub‐Product | # |
| Sub‐Product | 2 # |
| Market Value | * |
| Collateral Class | Non‐HQLA or Other |
| Collateral Level | # |
| Counterparty | # |
| G‐SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (36) Collateral Deliverables (§.32(f)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.DC.15 |
| Product | Matches PID |
| Sub‐Product | # |
| Sub‐Product | 2 # |
| Market Value | * |
| Collateral Class | HQLA |
| Collateral Level | # |
| Counterparty | # |
| G‐SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | N |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (37) Collateral Deliverables (§.32(f)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.DC.16 |
| Product | Matches PID |
| Sub‐Product | # |
| Sub‐Product | 2 # |
| Market Value | * |
| Collateral Class | # |
| Collateral Level | # |
| Counterparty | # |
| G‐SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (38) Collateral Substitution (§.32(f)(6))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.DC.18 and 20 |
| Product | Matches PID |
| Sub‐Product | # |
| Sub‐Product | 2 # |
| Market Value | * |
| Collateral Class | # |
| Collateral Level | # |
| Counterparty | # |
| G‐SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (39) Other Brokered Retail Deposits Maturing within 30 days (§.32(g)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.8 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days (but not open) |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (40) Other Brokered Retail Deposits Maturing later than 30 days (§.32(g)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.8 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | > 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (41) Insured Other Brokered Retail Deposits with No Maturity(§.32(g)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.8 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Open |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (42) Not Fully Insured Other Brokered Retail Deposits with No Maturity (§.32(g)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.8 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Open |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | Not FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (43) Insured Reciprocal (§.32(g)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.13 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (44) Not Fully Insured Reciprocal (§.32(g)(6))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.13 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | Not FDIC |
| Trigger | # |
| Rehypothecated | # Business Line |
| Internal | # |
| Internal Counterparty | # |

### (45) Insured Affiliated Sweeps (§.32(g)(7))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.9 and 10 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (46) Insured Non-Affiliated Sweeps (§.32(g)(8))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.11 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (47) Sweeps that are not Fully Insured (§.32(g)(9))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.9, 10 and 11 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | Not FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (48) Insured Unsecured Wholesale Non-Operational Non-Financial (§.32(h)(1)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.5 and 6 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank, GSE, PSE, MDB, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | NULL |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (49) Not Fully Insured Unsecured Wholesale Non-Operational Non-Financial (§.32(h)(1)(ii)(A))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.5 and 6 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank, GSE, PSE, MDB, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | NULL |
| Insured | Not FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (50) Not Fully Insured Unsecured Wholesale Non-Operational Non-Financial (§.32(h)(1)(ii)(A))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.W.9, 10, 17, 18 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank, GSE, PSE, MDB, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (51) Not Fully Insured Unsecured Wholesale Non-Operational Non-Financial (§.32(h)(1)(ii)(A))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3, 5, 6, 7, 11 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank, GSE, PSE, MDB, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Other |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (52) Unsecured Wholesale Brokered Deposit Non-Operational Non-Financial (§.32(h)(1)(ii)(B))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.8 – 11, 13 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank, GSE, PSE, MDB, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | NULL |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (53) Financial Non-Operational (§.32(h)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.5, 6, 8‐11 and 13 |
| Product | Matches PID |
| Counterparty | Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | NULL |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (54) Financial Non-Operational (§.32(h)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.W.9, 10, 17, and 18 |
| Product | Matches PID |
| Counterparty | Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (55) Financial Non-Operational (§.32(h)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3, 7, 11 |
| Product | Matches PID |
| Counterparty | Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Other |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (56) Issued Debt Securities Maturing within 30 Days (§.32(h)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.W.8, 11‐16 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | * |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (57) Insured Operational Deposits (§.32(h)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.4 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (58) Not Fully Insured Operational Deposits (§.32(h)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.4 |
| Product | Matches PID |
| Counterparty | All except Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | # |
| Insured | Not FDIC |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (59) Not Fully Insured Operational Deposits (§.32(h)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.7 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (60) Other Unsecured Wholesale (§.32(h)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.14 and 15 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (61) Other Unsecured Wholesale (§.32(h)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.W.19 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |

### (62) Other Unsecured Wholesale (§.32(h)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | No Collateral Pledged |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (63) Issued Not Structured Debt Securities Maturing Outside 30 Days when Primary Market Maker (§.32(i)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.L.4 |
| Product | Matches PID |
| Market Value | * |
| Collateral Class | # |
| Internal | # |
| Internal Counterparty | # |

### (64) Issued Structured Debt Securities Maturing Outside 30 Days when Primary Market Maker (§.32(i)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | S.L.5 |
| Product | Matches PID |
| Market Value | * |
| Collateral Class | # |
| Internal | # |
| Internal Counterparty | # *Footnotes appearing in the Secured Funding L1 tables regarding central bank secured funding apply to all other secured funding tables. |

### (65) Secured Funding L1 (§.32(j)(1)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.4, 5, 6 and 7 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank (FRB and other central banks where the sovereign has not established its own outflow rate)5, GSE, PSE, MDB, Other Supranational, Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days Maturity Optionality |
| Collateral Class | Level 1 HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (66) Secured Funding L1 (§.32(j)(1)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3, 5, 6 (FRB and other central banks where the sovereign has not established an LCR outflow rate)6, 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or Unsettled (Forward), For O.S.6, cannot be Covered Federal Reserve Facility Funding, # otherwise |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 1 HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Treasury Control | # 5 Central bank is determined by currency. For central banks whose currencies are not included in the major currencies reported, the outflow rate will be assumed to be 0% because the jurisdiction cannot be determined. 6 For O.S.6, if the counterparty is OCB, the outflow rate will be assumed to be 0% because the jurisdiction cannot be determined. |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank (FRB and other central banks where the sovereign has not established its own outflow rate), GSE, PSE, MDB, Other Supranational, Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |

### (67) Secured Funding L1 (§.32(j)(1)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.W.1‐7 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Level 1 HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (68) Secured Funding L2A (§.32(j)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.4 (not FDIC insured), 5, 6 and 7 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank (FRB and other central banks where the sovereign has not established its own outflow rate), GSE, PSE, MDB, Other Supranational, Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Level 2A HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Insured | If O.D.4 then not FDIC, otherwise # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (69) Secured Funding L2A (§.32(j)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3, 5, 6 (FRB and other central banks where the sovereign has not established an LCR outflow rate), 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or Unsettled (Forward), For O.S.6, cannot be Covered Federal Reserve Facility Funding, # otherwise |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Non‐Financial Corporate, Sovereign, Central Bank (FRB and other central banks where the sovereign has not established its own outflow rate), GSE, PSE, MDB, Other Supranational, Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |

### (70) Secured Funding L2A (§.32(j)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.W.1‐7 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Level 2A HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (71) Secured Funding from Governmental Entities not L1 or L2A (§.32(j)(1)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.4, 5 and 6 (if not FDIC insured) and 7 |
| Product | Matches PID |
| Counterparty | Sovereign, Central Bank (FRB and other central banks where the sovereign has not established its own outflow rate), GSE, or MDB |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Level 2B HQLA or Non‐HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Insured | Not FDIC for O.D.4‐6, # for O.D.7 |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (72) Secured Funding from Governmental Entities not L1 or L2A (§.32(j)(1)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3, 5, 6 (FRB and other central banks where the sovereign has not established an LCR outflow rate), 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or Unsettled (Forward), For O.S.6, cannot be Covered Federal Reserve Facility Funding unless the |
| Collateral Class | is Y‐1, Y‐2 or Y‐3, # otherwise |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA or Non‐HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Sovereign, Central Bank (FRB and other central banks where the sovereign has not established its own outflow rate), GSE, or MDB |
| G‐SIB | # |

### (73) Secured Funding L2B (§.32(j)(1)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.4 and 7 (only collateralized deposits)77 |
| Product | Matches PID 7 Secured deposits must meet the definition of a “collateralized deposit” under .32 of the LCR rule to be eligible for reporting under O.D.4 or O.D.7 (subject to the additional definitional requirements of these products). Secured deposits that do not meet the definition of a “collateralized deposit” should be reported under O.D.5 or O.D.6. |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Level 2B HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Insured | # |
| Trigger | # |
| Rehypothecated | Y |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (74) Secured Funding L2B (§.32(j)(1)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.5 and 6 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Pension Fund, Bank, Broker‐ Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐ Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other, |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Level 2B HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Insured | # |
| Trigger | # |
| Rehypothecated | Y for Non‐Financial Corporate, PSE, Other Supranational, Debt Issuing SPE, Other; # for Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (75) Secured Funding L2B (§.32(j)(1)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3, 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or Unsettled (Forward), # otherwise |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | Y for Non‐Financial Corporate, PSE, Other Supranational, Debt Issuing SPE, Other; # for Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund CID Matches Counterparty |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Pension Fund, Bank, Broker‐ Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐ Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |

### (76) Secured Funding L2B (§.32(j)(1)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.W.1‐7 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Level 2B HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (77) Customer Shorts Funded by Non-HQLA Customer Longs (§.32(j)(1)(v))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.7 |
| Product | Matches PID |
| Sub‐Product | Customer Long |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA |
| Collateral Value | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Pension Fund, Bank, Broker‐ Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐ Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |

### (78) Secured Funding Non-HQLA (§.32(j)(1)(vi))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.4 and 7 (only collateralized deposits) |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Pension Fund, Bank, Broker‐ Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Non‐HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Insured | # |
| Trigger | # |
| Rehypothecated | Y |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (79) Secured Funding Non-HQLA (§.32(j)(1)(vi))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.5 and 6 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Pension Fund, Bank, Broker‐ Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐ Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Non‐HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Insured | # |
| Trigger | # |
| Rehypothecated | Y for Non‐Financial Corporate, PSE, Other Supranational, Debt Issuing SPE, Other; # for Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (80) Secured Funding Non-HQLA (§.32(j)(1)(vi))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3, 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Customer Long, Unsettled (Regular Way) or Unsettled (Forward); #otherwise |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | Y for Non‐Financial Corporate, PSE, Other Supranational, Debt Issuing SPE, Other; # for Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Pension Fund, Bank, Broker‐ Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐ Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |

### (81) Secured Funding Non-HQLA (§.32(j)(1)(vi))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.W.1‐7 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Non‐HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale funding under .32(h) |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (82) Secured but Lower Unsecured Rate (§.32(j)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.5 and 6 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Level 2B HQLA or Non‐HQLA |
| Collateral Value | # |
| Insured | * |
| Trigger | # |
| Rehypothecated | N |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (83) Secured but Lower Unsecured Rate (§.32(j)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3, 5, 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7 must be firm long, otherwise # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA or Non‐HQLA |
| Collateral Value | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | N |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |

### (84) Secured but Lower Unsecured Rate (§.32(j)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.4 (only collateralized deposits) |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Pension Fund, Bank, Broker‐ Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other; if FDIC insured: Sovereigns, GSEs, MDBs, Central Bank (FRB and other central banks where the sovereign has not established its own outflow rate) |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | If FDIC insured: Not Level 1; if not FDIC insured: Level 2B or Non‐HQLA |
| Collateral Value | # |
| Insured | * |
| Trigger | # |
| Rehypothecated | N |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (85) Secured but Lower Unsecured Rate (§.32(j)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.7 (only collateralized deposits) |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, PSE, Other Supranational, Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐Regulated Fund, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Level 2B or Non‐HQLA |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | N |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (86) Asset Exchange Post L1 Receive L1 (§.32(j)(3)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 1 HQLA |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days but not open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 1 HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| CID | # |
| Counterparty | # |
| G‐SIB | # |

### (87) Asset Exchange Post L1 Receive L2A (§.32(j)(3)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2A HQLA |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days but not open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 1 HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| CID | # |
| Counterparty | # |
| G‐SIB | # |

### (88) Asset Exchange Post L1 Receive L2B (§.32(j)(3)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2B HQLA |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days but not open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 1 HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (89) Asset Exchange Post L1 Receive Non-HQLA (§.32(j)(3)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Non‐HQLA |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days but not open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 1 HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (90) Asset Exchange Post L2A Receive L1 or L2A (§.32(j)(3)(v))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 1 HQLA or level 2A HQLA |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days but not open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (91) Asset Exchange Post L2A Receive L2B (§.32(j)(3)(vi))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2B HQLA |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days but not open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (92) Asset Exchange Post L2A Receive Non-HQLA (§.32(j)(3)(vii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Non‐HQLA |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days but not open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # G‐SIB |

### (93) Asset Exchange Post L2B Receive L1, L2A or L2B (§.32(j)(3)(viii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | HQLA |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days but not open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (94) Asset Exchange Post L2B Receive Non-HQLA (§.32(j)(3)(ix))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Non‐HQLA |
| Maturity Amount | # |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL or <= 30 calendar days but not open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (95) Asset Exchange Post Rehypothecated Assets >30 days Receive L1 (§.32(j)(3)(x))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 1 HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | > 30 calendar days or Open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # G‐SIB |

### (96) Asset Exchange Post Rehypothecated Assets >30 days Receive L2A (§.32(j)(3)(xi))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2A HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | > 30 calendar days or Open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # G‐SIB |

### (97) Asset Exchange Post Rehypothecated Assets >30 days Receive L2B (§.32(j)(3)(xii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2B HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | > 30 calendar days or Open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (98) Asset Exchange Post Rehypothecated Assets >30 days Receive Non-HQLA (§.32(j)(3)(xiii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Non‐HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | > 30 calendar days or Open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (99) Foreign Central Banking Borrowing (§.32(k))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.D.4, 5, 6, 7 (only collateralized deposits) (foreign central banks where the sovereign has established an LCR outflow rate; if the foreign central bank has not established an outflow rate, then the outflow should be calculated through the secured funding tables above, see relevant footnotes above) |
| Product | Matches PID |
| Counterparty | Central Bank |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Collateral Class | Not NULL or Other |
| Collateral Value | * |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (100) Foreign Central Banking Borrowing (§.32(k))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.1, 2, 3 (foreign central banks where the sovereign has established an LCR outflow rate; if the foreign central bank has not established an outflow rate, then the outflow should be calculated through the secured funding tables above, see relevant footnotes above) |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Not Other |
| Collateral Value | * |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Central Bank |
| G‐SIB | # |

### (101) Foreign Central Banking Borrowing (§.32(k))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.S.6 (foreign central banks where the sovereign has established an LCR outflow rate; if the foreign central bank has not established an outflow rate, then the outflow should be calculated through the secured funding tables above) |
| Product | Matches PID |
| Sub‐Product | Specific central bank |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Not Other |
| Collateral Value | * |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Central Bank G‐SIB |

### (102) Other Contractual Outflows (§.32(l))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.19 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (103) Other Contractual Outflows (§.32(l))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | O.O.22 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

## INFLOW VALUES


### (104) Net Derivatives Cash Inflow Amount (§.33(b))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.O.7 |
| Product | Matches PID |
| Maturity Amount | * |
| Maturity Bucket | ≤ 30 calendar days |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Treasury Control | # |
| Counterparty | # |
| G‐SIB | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (105) Retail Cash Inflow Amount (§.33(c))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.U.5 and 6 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days but not Open |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Not Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (106) Retail Cash Inflow Amount (§.33(c))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days but not Open |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Not Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Retail or Small Business |
| G‐SIB | # |

### (107) Retail Cash Inflow Amount (§.33(c))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.O.6 |
| Product | Matches PID |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days but not Open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA loans, Other |
| Collateral Value | # |
| Treasury Control | # |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (108) Financial and Central Bank Cash Inflow Amount (§.33(d)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.U.1, 2, 4, 5, 6 and 8 |
| Product | Matches PID |
| Counterparty | Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund, Central Bank |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Not Segregated for Customer Protection or Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (109) Financial and Central Bank Cash Inflow Amount (§.33(d)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.A.3 |
| Product | Matches PID |
| Sub‐Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | <= 30 calendar days but not Open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | A‐0‐Q |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Internal Counterparty | # |

### (110) Financial and Central Bank Cash Inflow Amount (§.33(d)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Not Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Other |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund, Central Bank |
| G‐SIB | # |

### (111) Financial and Central Bank Cash Inflow Amount (§.33(d)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.O.6 |
| Product | Matches PID |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA loans, Other |
| Collateral Value | # |
| Treasury Control | # |
| Counterparty | Pension Fund, Bank, Broker‐Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non‐Bank Financial Entity, Non‐ Regulated Fund, Central Bank |
| G‐SIB | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (112) Non-Financial Wholesale Cash Inflow Amount (§.33(d)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.U.1, 2, and 6 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, GSE, PSE, MDB, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Not Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (113) Non-Financial Wholesale Cash Inflow Amount (§.33(d)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Not Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Other |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Non‐Financial Corporate, Sovereign, GSE, PSE, MDB, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |

### (114) Non-Financial Wholesale Cash Inflow Amount (§.33(d)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.O.6 |
| Product | Matches PID |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA loans, Other |
| Collateral Value | # |
| Treasury Control | # |
| Counterparty | Non‐Financial Corporate, Sovereign, GSE, PSE, MDB, Other Supranational, Debt Issuing SPE, Other |
| G‐SIB | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (115) Securities Cash Inflow Amount (§.33(e))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.O.6 and I.O.8 |
| Product | Matches PID |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days but not Open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA securities |
| Collateral Value | # |
| Treasury Control | # |
| Counterparty | # |
| G‐SIB | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (116) Securities Cash Inflow Amount (§.33(e))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.O.6 and I.O.8 |
| Product | Matches PID |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days but not Open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | HQLA |
| Collateral Value | # |
| Treasury Control | N |
| Counterparty | # |
| G‐SIB | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (117) Secured Lending when Asset Rehypothecated not returned within 30 days (§.33(f)(1)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, and 6 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | > 30 calendar days or Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | N |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (118) Secured Lending when Asset Available for Return (§.33(f)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (119) Secured Lending when Asset Available for Return (§.33(f)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | N |
| Treasury Control | Y |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (120) Secured Lending when Asset Available for Return (§.33(f)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | # |
| Treasury Control | N |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (121) Secured Lending with L1 HQLA (§.33(f)(1)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 1 HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (122) Secured Lending with L1 HQLA (§.33(f)(1)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 1 HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | Y |
| Treasury Control | Y |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (123) Secured Lending with L2A HQLA (§.33(f)(1)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (124) Secured Lending with L2A HQLA (§.33(f)(1)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | Y |
| Treasury Control | Y |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (125) Secured Lending with L2B HQLA (§.33(f)(1)(v))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (126) Secured Lending with L2B HQLA (§.33(f)(1)(v))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 5, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | NULL |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | Y |
| Treasury Control | Y |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (127) Secured Lending with Non-HQLA (§.33(f)(1)(vi))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.1, 2, 3, 6, 7 and 8 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA |
| Collateral Value | To the extent the Collateral Value is less than the |
| Maturity Amount | , treat the Maturity Amount less the Collateral Value amount as unsecured wholesale lending under .33(d) |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (128) Margin Loans for Non-HQLA (§.33(f)(1)(vii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.5 |
| Product | Matches PID |
| Sub‐Product | # |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (129) Asset Exchange Collateral Rehypothecated and Not Returning within 30 days (§.33(f)(2)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | * |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | > 30 calendar days or Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (130) Asset Exchange Post L1 Receive L1 (§.33(f)(2)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 1 HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 1 HQLA |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (131) Asset Exchange Post L2A Receive L1 (§.33(f)(2)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 1 HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (132) Asset Exchange Post L2B Receive L1 (§.33(f)(2)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 1 HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (133) Asset Exchange Post Non-HQLA Receive L1 (§.33(f)(2)(v))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 1 HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA or Other |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (134) Asset Exchange Post L2A Receive L2A (§.33(f)(2)(vi))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2A HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (135) Asset Exchange Post L2B Receive L2A (§.33(f)(2)(vii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2A HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (136) Asset Exchange Post Non-HQLA Receive L2A (§.33(f)(2)(viii))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2A HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA or Other |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (137) Asset Exchange Post L2B Receive L2B (§.33(f)(2)(ix))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2B HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (138) Asset Exchange Post Non-HQLA Receive L2B (§.33(f)(2)(x))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2B HQLA |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Maturity Optionality | # |
| Effective Maturity Bucket | <= 30 calendar days or NULL but not Open |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Non‐HQLA or Other |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

### (139) Broker-Dealer Segregated Account Inflow Amount (§.33(g))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.O.5 |
| Product | Matches PID |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Treasury Control | # |
| Counterparty | # |
| G‐SIB | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (140) Other Cash Inflow Amount (§.33(h))

| Field | Value |
|-------|-------|
| Reporting Entity | LCR Firm |
| PID | I.O.9 |
| Product | Matches PID |
| Maturity Amount | * |
| Maturity Bucket | <= 30 calendar days but not Open |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Treasury Control | # |
| Counterparty | # |
| G‐SIB | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |