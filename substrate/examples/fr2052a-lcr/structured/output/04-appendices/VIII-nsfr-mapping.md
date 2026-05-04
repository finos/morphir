# Appendix VIII: NSFR to FR 2052a Mapping

> **Hand-curated.** The NSFR formulas on pages 195–196 of the source PDF
> use Cambria Math font subsets with a broken ToUnicode CMap (same issue
> as Appendix VI). Formula text was transcribed from 12 CFR 249 §.100–§.109
> and the visible document structure.
> See [`human-annotations.md`](../../human-annotations.md) for details.
>
> Mapping tables (pages 197–253) extracted via `pdfplumber.extract_text()`.

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


## ASF Amount Values


**NSFR regulatory capital elements and NSFR liabilities assigned a 100 percent ASF factor (§.104(a))**


### (1) NSFR regulatory capital element (§.104(a)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.1 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | # |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | # |

### (2) Subordinated debt qualifying as an NSFR regulatory capital element (§.104(a)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.W.11, 12 |
| Product | Matches PID |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | Capital |
| Business Line | # |

### (3) Wholesale debt instruments maturing in ≥ 1 year, excluding deposits and securities financing transactions (§.104(a)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.W.1 – 13, 16, 17, 19 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | Not Capital |
| Business Line | # |

### (4) Wholesale deposits maturing in ≥ 1 year (§.104(a)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.5, 6, 8, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (5) Wholesale securities financing transactions maturing in ≥ 1 year (§.104(a)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.S.1, 2, 3, 5, 6, 11 |
| Product | Matches PID |
| Sub-Product | Not FRFF |
| Counterparty | Not Retail or Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Settlement | # |
| Rehypothecated | # |
| Business Line | # |

### (6) Wholesale interest payable in ≥ 1 year (§.104(a)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.O.19 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (7) Other liabilities maturing in ≥ 1 year (§.104(a)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.2 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | ≥ 1 Year |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | Not Retail or Small Business |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | # |

**NSFR liabilities assigned a 95 percent ASF factor (§.104(b))**


### (8) Stable retail deposits, excluding sweeps (§.104(b)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.1, 2 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (9) Insured stable affiliated retail sweep deposits (§.104(b)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.9 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

**NSFR liabilities assigned a 90 percent ASF factor (§.104(c))**


### (10) Not FDIC insured transactional and non-relationship retail deposits, excluding sweeps and brokered deposits (§.104(c)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.1, 2 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | Not FDIC |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (11) Non-relationship retail deposits, excluding sweeps and brokered deposits (§.104(c)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.3, O.D.14 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (12) Insured reciprocal brokered deposits (§.104(c)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.13 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | FDIC |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (13) Not FDIC insured affiliated relationship sweep deposits (§.104(c)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.9 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | Not FDIC |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (14) Less stable affiliated retail sweep deposits (§.104(c)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.10 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (15) Non-reciprocal brokered deposits maturing in ≥ 1 year (§.104(c)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.8 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

**NSFR liabilities assigned a 50 percent ASF factor (§.104(d))**


### (16) Unsecured wholesale non-deposit funding from non-financials maturing in < 1 year (§.104(d)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.W.9, 10, 17, 18, 19 |
| Product | Matches PID |
| Counterparty | Non-Financial Wholesale Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year2 |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (17) Unsecured wholesale deposit funding from non-financials maturing in < 1 year (§.104(d)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.5, 6, 8, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| Counterparty | Non-Financial Wholesale Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year |
| Maturity Optionality | # |
| Collateral Class | NULL |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

[^2]: In general, a Maturity Bucket condition of “less than” a certain time horizon without an explicit lower bound includes the “Open” maturity bucket unless stated otherwise (i.e., with the exclusion “but not Open”).


### (18) Securities financing transactions with non-financials maturing in < 1 year (§.104(d)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.S.1, 2, 3, 5, 7, 11 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Non-Financial Wholesale Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Settlement | # |
| Rehypothecated | # |
| Business Line | # |

### (19) Collateralized deposits from non-financials maturing in < 1 year (§.104(d)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.5, 6, 8, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| Counterparty | Non-Financial Wholesale Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year |
| Maturity Optionality | # |
| Collateral Class | Not NULL |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (20) Unsecured wholesale non-deposit funding from financials and central banks maturing in ≥ 6 months, but < 1 year (§.104(d)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.W.9, 10, 17, 18, 19 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (21) Unsecured wholesale deposit funding from financials and central banks maturing in ≥ 6 months, but < 1 year (§.104(d)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.5, 6, 8, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Maturity Optionality | # |
| Collateral Class | NULL |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (22) Securities financing transactions with financials and central banks maturing in ≥ 6 months, but < 1 year (§.104(d)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.S.1, 2, 3, 6, 11 |
| Product | Matches PID |
| Sub-Product | Not FRFF |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Settlement | # |
| Rehypothecated | # |
| Business Line | # |

### (23) Secured wholesale deposit funding from financials and central banks maturing in ≥ 6 months, but < 1 year (§.104(d)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.5, 6, 8, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Maturity Optionality | # |
| Collateral Class | Not NULL |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (24) Securities issued maturing in ≥ 6 months, but < 1 year (§.104(d)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.W.1 – 8, 11 – 16 |
| Product | Matches PID |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (25) Operational deposits (§.104(d)(6))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.4, 7 |
| Product | Matches PID |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (26) Non-reciprocal brokered retail deposits in transactional accounts and non-reciprocal brokered retail deposits maturing in ≥ 6 months, but < 1 year (§.104(d)(7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.8 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | Open or ≥ 6 Months, < 1 Year |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (27) Non-affiliated retail sweep deposits (§.104(d)(8))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.11 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (28) Other unsecured funding from retail customers (§.104(d)(9))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.W.18, 19 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (29) Other secured funding from retail customers (§.104(d)(9))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.S.1, 2, 3, 7, 11 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Settlement | # |
| Rehypothecated | # |
| Business Line | # |

### (30) Interest payable to retail customers (§.104(d)(9))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.O.19 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (31) Other liabilities to retail customers (§.104(d)(9))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.2 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | # |

### (32) Interest payable to wholesale entities in ≥ 6 months, but < 1 year (§.104(d)(10))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.O.19 |
| Product | Matches PID |
| Counterparty | Not Retail or Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (33) Other liabilities to wholesale entities maturing in ≥ 6 months, but < 1 year (§.104(d)(10))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.2 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | Not Retail or Small Business |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | # |

**NSFR liabilities assigned a zero percent ASF factor (§.104(e))**


### (34) Trade date payables (§.104(e)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.5 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | # |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | * |
| Forward Start Bucket | # |
| Collateral Class | # |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Internal Counterparty | # |

### (35) Non-reciprocal brokered retail deposits maturing in < 6 months (§.104(e)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.8 |
| Product | Matches PID |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months, but not Open |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (36) Securities issued maturing in < 6 months (§.104(e)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.W.1 – 8, 11 – 16 |
| Product | Matches PID |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (37) Unsecured wholesale non-deposit funding from financials and central banks maturing in < 6 months (§.104(e)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.W.9, 10, 17, 18, 19 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Loss Absorbency | # |
| Business Line | # |

### (38) Unsecured wholesale deposit funding from financials and central banks maturing in < 6 months (§.104(e)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.D.5, 6, 8, 10, 11, 13, 14, 15 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Insured | # |
| Trigger | # |
| Rehypothecated | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (39) Securities financing transactions with financials and central banks maturing in < 6 months (§.104(e)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.S.1, 2, 3, 6, 7, 11 |
| Product | Matches PID |
| Sub-Product | Not FRFF |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Settlement | # |
| Rehypothecated | # |
| Business Line | # |

### (40) Interest payable to financials and central banks in < 6 months (§.104(e)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.O.19 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (41) Other liabilities to financials and central banks maturing in < 6 months (§.104(e)(4))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.2 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | < 6 Months |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | # |

### (42) Firm short positions (§.104(e)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.S.8 |
| Product | Matches PID |
| Sub-Product | Not Unsettled (Forward) |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Settlement | # |
| Rehypothecated | # |
| Business Line | # |

### (43) Interest payable to non-financial wholesale entities in < 6 months (§.104(e)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.O.19 |
| Product | Matches PID |
| Counterparty | Non-Financial Wholesale Entity or NULL |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (44) Other liabilities maturing in < 6 months (§.104(e)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.2 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | < 6 Months |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | Non-Financial Wholesale Entity or NULL |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | # |

## RSF Amount Values


**Unencumbered assets assigned a zero percent RSF factor (§.106(a)(1))**


### (45) Currency and coin (§.106(a)(1)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.3, 4 |
| Product | Matches PID |
| Sub-Product | Currency and Coin |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | A-0-Q |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Internal Counterparty | # |

### (46) Cash items in process (§.106(a)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.7 |
| Product | Matches PID |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (47) Central bank reserve balances (§.106(a)(1)(iii) & (iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.3, 4 |
| Product | Matches PID |
| Sub-Product | Not Currency and Coin |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | < 6 Months |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | A-0-Q |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Internal Counterparty | # |

### (48) Central bank debt securities maturing in < 6 months (§.106(a)(1)(iii) & (iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 3, 4, 5, 7 |
| Product | Matches PID |
| Sub-Product | For I.A.3 and 4, Not Currency and Coin |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | < 6 Months |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | CB-1-Q, CB-2-Q, CB-3-Q, CB-1, CB-2, CB-3, CB-4 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (49) Unsecured lending to central banks maturing in < 6 months (§.106(a)(1)(iii) & (iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1 – 6, 8 |
| Product | Matches PID |
| Counterparty | Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (50) Secured lending to central banks maturing in < 6 months (§.106(a)(1)(iii) & (iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5 – 8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
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

### (51) Interest receivable from central banks in < 6 months (§.106(a)(1)(iii) & (iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.O.6 |
| Product | Matches PID |
| Counterparty | Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Collateral Class | # |
| Co llateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (52) Level 1 HQLA central bank securities (§.106(a)(1)(iii) & (iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 3, 4, 5, 7 |
| Product | Matches PID |
| Sub-Product | For I.A.3 and 4, Not Currency and Coin |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | ≥ 6 Months |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | CB-1-Q, CB-2-Q |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (53) Trade date receivables that are expected to settle (§.106(a)(1)(v))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.S.8 |
| Product | Matches PID |
| Sub-Product | Unsettled (Regular Way) |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | # |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | * |
| Forward Start Bucket | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Settlement | # |
| Rehypothecated | # |
| Business Line | # |

### (54) Other level 1 HQLA securities (§.106(a)(1)(vi))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 5, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | A-1-Q, A-2-Q, A-3-Q, A-4-Q, A-5-Q, S-1-Q, S-2-Q, S-<br>3-Q, S-4-Q |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (55) Lending to financials secured by rehypothecatable level 1 HQLA (§.106(a)(1)(vii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5, 6 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
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

**Unencumbered assets and commitments assigned a 5 percent RSF factor (§.106(a)(2))**


### (56) Undrawn commitments (§.106(a)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | O.O.4, 5, 6 |
| Product | Matches PID |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year |
| Collateral Class | # |
| Collateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

**Unencumbered assets assigned a 15 percent RSF factor (§.106(a)(3))**


### (57) Level 2A HQLA central bank securities (§.106(a)(3)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 3, 4, 5, 7 |
| Product | Matches PID |
| Sub-Product | For I.A.3 and 4, Not Currency and Coin |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | ≥ 6 Months |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | CB-3-Q |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (58) Other level 2A HQLA securities (§.106(a)(3)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 5, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | Level 2A HQLA, but Not CB-3-Q |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (59) Lending to financials secured by rehypothecatable non-level 1 HQLA collateral maturing in < 6 months (§.106(a)(3)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5, 6 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Not Level 1 HQLA |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |
| Settlement | # |

### (60) Other secured lending to financials maturing in < 6 months (§.106(a)(3)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.7, 8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
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

### (61) Unsecured lending to financials maturing in < 6 months (§.106(a)(3)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1, 2, 4, 5, 6, 8 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 6 Months |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

**Unencumbered assets assigned a 50 percent RSF factor (§.106(a)(4))**


### (62) Level 2B HQLA securities (§.106(a)(4)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 5, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | Level 2B HQLA |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (63) Secured lending to financials and central banks, maturing in ≥ 6 months, but < 1 year (§.106(a)(4)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5, 6, 7, 8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
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

### (64) Unsecured lending to financials and central banks, maturing in ≥ 6 months, but < 1 year (§.106(a)(4)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1, 2, 4, 5, 6, 8 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (65) Operational deposits placed (§.106(a)(4)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.3 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (66) Secured lending to non-financials maturing in < 1 year (§.106(a)(4)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5, 6, 7, 8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Retail, Small Business, Non-Financial Wholesale<br>Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
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

### (67) Unsecured lending to non-financials maturing in < 1 year (§.106(a)(4)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1, 2, 5, 6 |
| Product | Matches PID |
| Counterparty | Retail, Small Business, Non-Financial Wholesale<br>Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (68) Interest receivable from central banks in ≥ 6 months, but < 1 year (§.106(a)(4)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.O.6 |
| Product | Matches PID |
| Counterparty | Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Collateral Class | # |
| Co llateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (69) Non-HQLA central bank debt securities maturing in ≥ 6 months, but < 1 year (§.106(a)(4)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 3, 4, 5, 7 |
| Product | Matches PID |
| Sub-Product | For I.A.3 and 4, Not Currency and Coin |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | ≥ 6 Months, < 1 Year |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | CB-1, CB-2, CB-3, CB-4 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (70) Other unencumbered non-HQLA securities maturing in < 1 year (§.106(a)(4)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 5, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | < 1 Year |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | A-2, A-3, A-4, A-5, S-1, S-2, S-3, S-4, G-1, G-2, G-3,<br>S-5, S-6, S-7, IG-1, IG-2, S-8, G-4, E-5, E-6, E-7, E-8,<br>E-9, E-10, IG-3, IG-4, IG-5, IG-6, IG-7, IG-8, N-1,<br>N-2, N-3, N-4, N-5, N-6, N-7, N-8, Y-1, Y-2, Y-3 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 6 Months or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (71) Other interest receivable in < 1 year (§.106(a)(4)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.O.6 |
| Product | Matches PID |
| Counterparty | Not Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year |
| Collateral Class | # |
| Co llateral Value | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

**Unencumbered assets assigned a 65 percent RSF factor (§.106(a)(5))**


### (72) Retail mortgages with ≤ 50% risk weight maturing in ≥ 1 year (§.106(a)(5)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | P-1 |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | ≤ 0.5 |
| Business Line | # |
| Settlement | # |

### (73) Other secured retail loans with ≤ 20% risk weight maturing in ≥ 1 year (§.106(a)(5)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Not P-1 |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | ≤ 0.2 |
| Business Line | # |
| Settlement | # |

### (74) Secured non-financial wholesale and central bank loans with ≤ 20% risk weight maturing in ≥ 1 year (§.106(a)(5)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Non-Financial Wholesale Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | ≤ 0.2 |
| Business Line | # |
| Settlement | # |

### (75) Securities financing transactions assigned ≤ 20% risk weight provided to non-financial customers and maturing in ≥ 1 year (§.106(a)(5)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5, 6, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Not Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | ≤ 0.2 |
| Business Line | # |
| Settlement | # |

### (76) Unsecured loans assigned ≤ 20% risk weight provided to non-financial customers and maturing in ≥ 1 year (§.106(a)(5)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1, 2, 5, 6 |
| Product | Matches PID |
| Counterparty | Not Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | ≤ 0.2 |
| Business Line | # |

**Unencumbered assets assigned an 85 percent RSF factor (§.106(a)(6))**


### (77) Retail mortgages with > 50% risk weight maturing in ≥ 1 year (§.106(a)(6)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | P-1 |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | > 0.5 |
| Business Line | # |
| Settlement | # |

### (78) Other secured retail loans with > 20% risk weight maturing in ≥ 1 year (§.106(a)(6)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Retail, Small Business |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | Not P-1 |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | > 0.2 |
| Business Line | # |
| Settlement | # |

### (79) Secured non-financial wholesale and central bank loans with > 20% risk weight maturing in ≥ 1 year (§.106(a)(6)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Non-Financial Wholesale Entity, Central Bank |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | > 0.2 |
| Business Line | # |
| Settlement | # |

### (80) Securities financing transactions assigned > 20% risk weight provided to non-financial customers and maturing in ≥ 1 year (§.106(a)(6)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5, 6, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Not Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | # |
| Collateral Value | # |
| Unencumbered | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | > 0.2 |
| Business Line | # |
| Settlement | # |

### (81) Unsecured loans assigned > 20% risk weight provided to non-financial customers and maturing in ≥ 1 year (§.106(a)(6)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1, 2, 5, 6 |
| Product | Matches PID |
| Counterparty | Not Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | > 0.2 |
| Business Line | # |

### (82) Non-HQLA common equity shares (§.106(a)(6)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 5, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | E-1, E-2, E-3, E-4 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (83) Other non-HQLA securities maturing in ≥ 1 year (§.106(a)(6)(iv))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 3, 4, 5, 7 |
| Product | Matches PID |
| Sub-Product | For I.A.3 and 4, Not Currency and Coin |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | ≥ 1 Year |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | A-2, A-3, A-4, A-5, S-1, S-2, S-3, S-4, CB-1, CB-2,<br>G-1, G-2, G-3, S-5, S-6, S-7, CB-3, IG-1, IG-2, S-8,<br>CB-4, G-4, E-5, E-6, E-7, E-8, E-9, E-10, IG-3, IG-4,<br>IG-5, IG-6, IG-7, IG-8, N-1, N-2, N-3, N-4, N-5, N-6,<br>N-7, N-8, Y-1, Y-2, Y-3, Y-4 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (84) Commodities (§.106(a)(6)(v))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 5, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | C-1 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

**Unencumbered assets assigned a 100 percent RSF factor (§.106(a)(7))**


### (85) Secured lending to financial sector entities maturing in ≥ 1 year (§.106(a)(7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5, 6, 7, 8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
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

### (86) Unsecured lending to financial sector entities maturing in ≥ 1 year (§.106(a)(7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1, 2, 4, 5, 6, 8 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (87) Physical property and other assets (§.106(a)(7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 5, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | P-1, P-2, Z-1 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (88) Other assets (§.106(a)(7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.4 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | # |
| Effective Maturity Bucket | < 1 Year or NULL |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | # |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | #<br>Nonperforming assets (§.106(b)) |

### (89) Nonperforming assets (§.106(b))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.3 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | # |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | #<br>Encumbered assets with six months or more, but less than one year, remaining in the<br>encumbrance period (§.106(c)(1)(ii))3 |

### (90) HQLA encumbered for ≥ 6 Months, but < 1 Year (§.106(c)(1)(ii) & §.106(d)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | HQLA |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | ≥ 6 Months, < 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (91) Non-HQLA central bank securities maturing in < 1 Year, encumbered for ≥ 6 Months, but < 1 Year (§.106(c)(1)(ii) & §.106(d)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | < 1 Year |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | CB-1, CB-2, CB-3, CB-4 |
| Treasury Control | # |
| Accounting Designation | # |

[^3]: The tables in this section include only assets with an RSF of 50 percent or less, and thus are assigned an equivalent or higher RSF based on the remaining encumbrance period (see: §.106(c)(1)(ii)(A)). Assets with an RSF higher than 50 percent are included in the tables for unencumbered assets (see: §.106(c)(1)(ii)(B))

| Effective Maturity Bucket | ≥ 6 Months, < 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (92) Cash items in process encumbered for ≥ 6 months, but < 1 year (§.106(c)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.7 |
| Product | Matches PID |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Effective Maturity Bucket | ≥ 6 Months, < 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (93) Unsecured lending maturing in < 1 year, encumbered for ≥ 6 months, but < 1 year (§.106(c)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1, 2, 4, 5, 6, 8 |
| Product | Matches PID |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | ≥ 6 Months, < 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (94) Operational deposits placed, encumbered for ≥ 6 months, but < 1 year (§.106(c)(1)(ii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.3 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Effective Maturity Bucket | ≥ 6 Months, < 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (95) Secured lending maturing in < 1 year, encumbered for ≥ 6 months, but < 1 year (§.106(c)(1)(ii) & §.106(d)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5 – 8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | < 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | ≥ 6 Months, < 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
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

### (96) Non-HQLA securities maturing in < 1 year, encumbered for ≥ 6 months, but < 1 year (§.106(c)(1)(ii) & §.106(d)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | < 1 Year |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | A-2, A-3, A-4, A-5, S-1, S-2, S-3, S-4, G-1, G-2, G-3,<br>S-5, S-6, S-7, IG-1, IG-2, S-8, G-4, E-5, E-6, E-7, E-8,<br>E-9, E-10, IG-3, IG-4, IG-5, IG-6, IG-7, IG-8, N-1,<br>N-2, N-3, N-4, N-5, N-6, N-7, N-8, Y-1, Y-2, Y-3 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | ≥ 6 Months, < 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | #<br>Encumbered assets with one year or more remaining in the encumbrance period |

### (97) HQLA, non-HQLA and other assets, excluding loans, encumbered for ≥ 1 year (§.106(c)(1)(iii), §.106(d)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | # |
| Forward Start Bucket | # |
| Collateral Class | HQLA, A-2, A-3, A-4, A-5, S-1, S-2, S-3, S-4, CB-1,<br>CB-2, G-1, G-2, G-3, S-5, S-6, S-7, CB-3, E-1, E-2,<br>IG-1, IG-2, S-8, CB-4, E-3, E-4, E-5, E-6, E-7, E-8, E-9,<br>E-10, IG-3, IG-4, IG-5, IG-6, IG-7, IG-8, N-1, N-2,<br>N-3, N-4, N-5, N-6, N-7, N-8, Y-1, Y-2, Y-3, C-1, P-1,<br>P-2, Z-1 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | ≥ 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Internal Counterparty | # |

### (98) Unsecured loans and other cash items encumbered for ≥ 1 year (§.106(c)(1)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1 – 8 |
| Product | Matches PID |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Effective Maturity Bucket | ≥ 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (99) Secured lending transactions encumbered for ≥ 1 year (§.106(c)(1)(iii) & §.106(d)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5 – 8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | # |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | # |
| Maturity Optionality | # |
| Effective Maturity Bucket | ≥ 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
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

### (100) Other assets encumbered for ≥ 1 year (§.106(c)(1)(iii))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.4 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | # |
| Effective Maturity Bucket | ≥ 1 Year |
| Encumbrance Type | Not Derivative VM, Derivative IM and DFC or<br>Covered Federal Reserve Facility Funding |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | # |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | # |

### (101) Additional RSF associated with off-balance sheet rehypothecated assets (§.106(d)(3))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.L.9 |
| Product | Matches PID |
| Collateral Class | # |
| Market Value | * |
| Internal | # |
| Internal Counterparty | # |

**Calculation of NSFR derivatives amounts (§.107)**


### (102) Gross NSFR derivative liability amount (§.107(b)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.DC.2 |
| Product | Matches PID |
| Sub-Product | # |
| Sub-Product2 | Not OTC – Centralized (Agent) or Exchange-traded<br>(Agent) |
| Market Value | * |
| Collateral Class | # |
| Collateral Level | # |
| Counterparty | # |
| G-SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (103) Gross settlement payments delivered (§.107(b)(5))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.DC.3 |
| Product | Matches PID |
| Sub-Product | # |
| Sub-Product2 | Not OTC – Centralized (Agent) or Exchange-traded<br>(Agent) |
| Market Value | * |
| Collateral Class | # |
| Collateral Level | # |
| Counterparty | # |
| G-SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (104) Central counterparty mutualized loss sharing arrangements (§.107(b)(6))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.DC.11 |
| Product | Matches PID |
| Sub-Product | # |
| Sub-Product2 | # |
| Market Value | * |
| Collateral Class | # |
| Collateral Level | # |
| Counterparty | # |
| G-SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (105) Initial margin provided (§.107(b)(7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.DC.5, 6 |
| Product | Matches PID |
| Sub-Product | # |
| Sub-Product2 | Not OTC – Centralized (Agent) or Exchange-traded<br>(Agent) |
| Market Value | * |
| Collateral Class | # |
| Collateral Level | # |
| Counterparty | # |
| G-SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (106) Additional RSF for IM and DFC pledged – secured lending (§.107(b)(6) & (7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.S.1, 2, 3, 5, 6, 7, 8 |
| Product | Matches PID |
| Sub-Product | # |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Derivative IM and DFC |
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

### (107) Additional RSF for IM and DFC pledged – unsecured lending (§.107(b)(6) & (7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.U.1, 2, 4, 5, 6, 8 |
| Product | Matches PID |
| Counterparty | Financial Sector Entity |
| G-SIB | # |
| Maturity Amount | * |
| Maturity Bucket | ≥ 1 Year |
| Maturity Optionality | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Derivative IM and DFC |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Internal | # |
| Internal Counterparty | # |
| Risk Weight | # |
| Business Line | # |

### (108) Additional RSF for IM and DFC pledged – physical and other (§.107(b)(6) & (7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | I.A.1, 2, 5, 7 |
| Product | Matches PID |
| Sub-Product | # |
| Market Value | * |
| Lendable Value | # |
| Maturity Bucket | # |
| Forward Start Amount | NULL |
| Forward Start Bucket | NULL |
| Collateral Class | P-1, P-2, Z-1 |
| Treasury Control | # |
| Accounting Designation | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Derivative IM and DFC |
| Internal Counterparty | # |

### (109) Additional RSF for IM and DFC pledged – other assets (§.107(b)(6) & (7))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| Collection Reference | # |
| PID | S.B.4 |
| Product | Matches PID |
| Sub-Product | # |
| Product Reference | # |
| Sub-Product Reference | # |
| Collateral Class | # |
| Maturity Bucket | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | Derivative IM and DFC |
| Market Value | # |
| Maturity Amount | * |
| Collateral Value | # |
| Counterparty | # |
| G-SIB | # |
| Risk Weight | # |
| Internal | # |
| Internal Counterparty | # |

### (110) Gross NSFR derivative asset amount (§.107(f)(1))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.DC.1 |
| Product | Matches PID |
| Sub-Product | # |
| Sub-Product2 | Not OTC – Centralized (Agent) or Exchange-traded<br>(Agent) |
| Market Value | * |
| Collateral Class | # |
| Collateral Level | # |
| Counterparty | # |
| G-SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (111) Variation margin received eligible for netting (§.107(f)(1)(i))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.DC.10 |
| Product | Matches PID |
| Sub-Product | Rehypothecatable – Unencumbered,<br>Rehypothecatable – Encumbered,<br>Non-Segregated Cash |
| Sub-Product2 | Not OTC – Centralized (Agent) or Exchange-traded<br>(Agent) |
| Market Value | * |
| Collateral Class | Level 1 HQLA |
| Collateral Level | Not Overcollateralized4 |
| Counterparty | # |
| G-SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | Y |
| Treasury Control | # |

[^4]: “Overcollateralized” should designate only the portion of variation margin received that exceeds the current asset value of a netting set.

| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (112) NSFR derivative liability amount (§.107(f)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.DC.2 |
| Product | Matches PID |
| Sub-Product | # |
| Sub-Product2 | Not OTC – Centralized (Agent) or Exchange-traded<br>(Agent) |
| Market Value | * |
| Collateral Class | # |
| Collateral Level | # |
| Counterparty | # |
| G-SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |
| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

### (113) Variation margin provided, excluding overcollateralized portion (§.107(f)(2))

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.DC.8 and 9 |
| Product | Matches PID |
| Sub-Product | # |
| Sub-Product2 | Not OTC – Centralized (Agent) or Exchange-traded<br>(Agent) |
| Market Value | * |
| Collateral Class | # |
| Collateral Level | Not Overcollateralized5 |
| Counterparty | # |
| G-SIB | # |
| Effective Maturity Bucket | # |
| Encumbrance Type | # |
| Netting Eligible | # |

[^5]: Overcollateralized should designate only the portion of variation margin pledged that exceeds the current liability value of a netting set.

| Treasury Control | # |
| Internal | # |
| Internal Counterparty | # |
| Business Line | # |

**Rules for consolidation (§.109)**


### (114) Deduction of non-transferrable excess subsidiary stable funding (§.109)

| Field | Value |
|-------|-------|
| Reporting Entity | NSFR Entity |
| PID | S.L.7 |
| Product | Matches PID |
| Collateral Class | # |
| Market Value | * |
| Internal | # |
| Internal Counterparty | # |
