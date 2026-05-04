# Appendix VII: Short-Term Wholesale Funding (STWF) to FR 2052a Mapping

> **Hand-curated.** Extracted via `pdfplumber.extract_text()` (pages 180–194).
> No font issues; tables extract cleanly. See
> [`human-annotations.md`](../../human-annotations.md) for layout notes.

Staff of the Board of Governors of the Federal Reserve System (Board) has developed this document to assist reporting firms that must file Schedule G or N (STWF Indicator) of the FR Y‐15 (Banking Organization Systemic Risk Report) in mapping the specific line items on Schedule G or N to the unique data identifiers reported on the FR 2052a. This mapping document is not a part of any regulation nor a component of official guidance related to the FR 2052a or FR Y‐15 reports. Firms may use this mapping document solely at their discretion. From time to time, to ensure accuracy, an updated mapping document may be published and reporting firms will be notified of these changes.

## Key

| Symbol | Meaning |
|--------|---------|
| `\*` | Values relevant to Schedule G or N of the FR Y‐15 |
| `#` | Values not relevant to Schedule G or N of the FR Y‐15 |
| `NULL` | Should not have an associated value |


## FR 2052a to FR Y-15, Schedule G Map

## Item 1.a: Funding secured by level 1 liquid assets (sum of tables 1‐3)

### (1) O.D. PIDs for item 1.a

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.D.5, 6, 8, 9, 10, 11, 13, 14 ,15 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | Level 1 HQLA |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (2) O.S. PIDs for item 1.a

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.S.1, 2, 3, 5, 6, 7 and 11 |
| Product | Matches PID |
| Sub‐product | For O.S.7, cannot be Unsettled (Regular Way) or<br>Unsettled (Forward), # otherwise |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 1 HQLA |
| Collateral Value | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (3) O.W. PIDs for item 1.a

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| Currency | * |
| Converted | # |
| PID | O.W.1‐7, 9‐19 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | Level 1 HQLA |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

## Item 1.b: Retail brokered deposits and sweeps (table 4)

### (4) O.D. PIDs for item 1.b

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.D.8, 9, 10, 11 and 13 |
| Product | Matches PID |
| Counterparty | Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

## Item 1.c: Unsecured wholesale funding obtained outside of the financial sector (sum of
tables 5 and 6)

### (5) O.D. PIDs for item 1.c

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.D.5, 6, 8, 9, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| CID | Matches Counterparty |
| Counterparty | Non‐Financial Corporate, Sovereign, Central<br>Bank, GSE, PSE, MDB, Other Supranational, Debt<br>Issuing SPE, Other |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Loss Absorbency | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (6) O.W. PIDs for item 1.c

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.W.9, 10, 17, 18, 19 |
| Product | Matches PID |
| Counterparty | Non‐Financial Corporate, Sovereign, Central<br>Bank, GSE, PSE, MDB, Other Supranational, Debt<br>Issuing SPE, Other |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | NULL |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (7) O.S. PIDs for item 1.c

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.S.1, 2, 3, 5, 6, 7 and 11 |
| Product | Matches PID |
| Sub‐product | For O.S.7, cannot be Unsettled (Regular Way) or<br>Unsettled (Forward), # otherwise |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Other |
| Collateral Value | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Non‐Financial Corporate, Sovereign, Central<br>Bank, GSE, PSE, MDB, Other Supranational, Debt<br>Issuing SPE, Other |
| G‐SIB | # |

### (8) I.S. PIDs for item 1.c

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | No Collateral Pledged |
| Maturity Amount | # |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Non‐Financial Corporate, Sovereign, Central<br>Bank, GSE, PSE, MDB, Other Supranational, Debt<br>Issuing SPE, Other |
| G‐SIB | # |

## Item 1.d: Firm short positions involving level 2B liquid assets or non‐HQLA (table 7)

### (9) O.S. PIDs for item 1.d

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| Currency | * |
| Converted | # |
| PID | O.S.8 |
| Product | Matches PID |
| Sub‐Product | External Cash Transaction, External Non‐Cash<br>Transaction, Customer Longs |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | Level 2B HQLA or Non‐HQLA |
| Collateral Value | # |
| Collateral Currency | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | # |
| G‐SIB | # |

## Item 2.a: Funding secured by level 2A liquid assets (sum of tables 8‐10)

### (10) O.D. PIDs for item 2.a

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.D.5, 6, 8, 9, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | Level 2A HQLA |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (11) O.S. PIDs for item 2.a

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.S.1, 2, 3, 5, 6, 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or<br>Unsettled (Forward), # otherwise |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (12) O.W. PIDs for item 2.a

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.W.1‐7, 9‐19 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | Level 2A HQLA |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

## Item 2.b: Covered asset exchanges (level 1 to level 2A) (table 11)

### (13) O.S. PIDs for item 2.b

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 1 Received |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2A HQLA |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | # |
| G‐SIB | # |

## Item 3.a: Funding secured by level 2B liquid assets (sum of tables 12‐14)

### (14) O.D. PIDs for item 3.a

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.D.5, 6, 8, 9, 10, 11, 13, 14 and 15 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | Level 2B HQLA |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (15) O.S. PIDs for item 3.a

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.S.1, 2, 3, 5, 6, 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or<br>Unsettled (Forward), # otherwise |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Level 2B HQLA |
| Collateral Value | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (16) O.W. PIDs for item 3.a

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.W.1‐7, 9‐19 |
| Product | Matches PID |
| Counterparty | # |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | Level 2B HQLA |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

## Item 3.b: Other covered asset exchanges (table 15)

### (17) I.S. PIDs for item 3.b

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | Level 2b Pledged, Non‐HQLA Pledged |
| Maturity Amount | # |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | For Sub‐Product value of Level 2b Pledged: Level 1<br>or Level 2A HQLA; For Sub‐Product values of Non‐<br>HQLA Pledged: all HQLA |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | # |
| G‐SIB | # |

## Item 3.c: Unsecured wholesale funding obtained within the financial sector (sum of tables
16 and 17)

### (18) O.D. PIDs for item 3.c

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.D.5, 6, 8, 9, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| Counterparty | Pension Fund, Bank, Broker‐Dealer, Investment<br>Company or Advisor, Financial Market Utility,<br>Other Supervised Non‐Bank Financial Entity, Non‐<br>Regulated Fund |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (19) O.W. PIDs for item 3.c

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.W.1‐19 |
| Product | Matches PID |
| Counterparty | For O.W.1 ‐ 8, 11 ‐ 16: #; For O.W.9, 10, 17, 18, 19:<br>Pension Fund, Bank, Broker‐Dealer, Investment<br>Company or Advisor, Financial Market Utility,<br>Other Supervised Non‐Bank Financial Entity,<br>Non‐Regulated Fund, or NULL |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | NULL or Other |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (20) O.S. PIDs for item 3.c

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.S.1, 2, 3, 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or<br>Unsettled (Forward), # otherwise |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Other |
| Collateral Value | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |
| Settlement | # |
| Rehypothecated | # |
| Counterparty | Pension Fund, Bank, Broker‐Dealer, Investment<br>Company or Advisor, Financial Market Utility,<br>Other Supervised Non‐Bank Financial Entity, Non‐<br>Regulated Fund |
| G‐SIB | # |

### (21) I.S. PIDs for item 3.c

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | I.S.4 |
| Product | Matches PID |
| Sub‐Product | No Collateral Pledged |
| Maturity Amount | # |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | * |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |
| Counterparty | Pension Fund, Bank, Broker‐Dealer, Investment<br>Company or Advisor, Financial Market Utility,<br>Other Supervised Non‐Bank Financial Entity, Non‐<br>Regulated Fund |
| G‐SIB | # |

## Item 4: All other components of short‐term wholesale funding (sum of tables 18‐20)

### (22) O.D. PIDs for item 4

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.D.5, 6, 8, 9, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | Non‐HQLA |
| Collateral Value |  |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Business Line | # |
| Internal | # |
| Internal Counterparty | # |

### (23) O.S. PIDs for item 4

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.S.1, 2, 5, 6, 7 and 11 |
| Product | Matches PID |
| Sub‐Product | For O.S.7, cannot be Unsettled (Regular Way) or<br>Unsettled (Forward), # otherwise |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
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
| Counterparty | Not Retail or Small Business |
| G‐SIB | # |

### (24) O.W. PIDs for item 4

| Field | Value |
|-------|-------|
| Reporting Entity | FR Y‐15 Firm |
| PID | O.W.1‐7 |
| Product | Matches PID |
| Counterparty | # |
| Maturity Amount | * |
| Maturity Bucket | Column A: <=30 days<br>Column B: 31 to 90 days<br>Column C: 91 to 180 days<br>Column D: 181 days to 1 yr |
| Maturity Optionality | # |
| Collateral Class | Non‐HQLA |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |
