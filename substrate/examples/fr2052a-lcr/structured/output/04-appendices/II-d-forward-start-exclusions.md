# Appendix II-d: FR 2052a Forward Start Exclusions

> This file is **hand-curated** with the help of human visual annotations
> recorded in [`../../human-annotations.md`](../../human-annotations.md).
> The splitter (`scripts/extract.py`) does not overwrite this file on re-run.

The following products should not be assigned a `[Forward Start Bucket]` or
`[Forward Start Amount]` value.

The original list spans three pages of the source PDF and groups products
by table. Rendered here as a single nested bullet list.

- **Inflows - Assets**
  - I.A.1 — Unencumbered Assets
  - I.A.2 — Capacity
  - I.A.3 — Unrestricted Reserve Balances
  - I.A.4 — Restricted Reserve Balances
  - I.A.7 — Encumbered Assets
- **Inflows - Unsecured**
  - I.U.3 — Required Operational Balances
  - I.U.4 — Excess Operational Balances
  - I.U.7 — Cash Items in the Process of Collection
  - I.U.8 — Short-Term Investments
- **Inflows - Other**
  - I.O.1 — Derivative Receivables
  - I.O.2 — Collateral Called for Receipt
  - I.O.3 — TBA Sales
  - I.O.4 — Undrawn Committed Facilities Purchased
  - I.O.5 — Lock-up Balance
  - I.O.6 — Interest and Dividends Receivable
  - I.O.7 — Net 30-Day Derivative Receivables
  - I.O.8 — Principal Payments Receivable on Unencumbered Investment Securities
  - I.O.9 — Other Cash Inflows
- **Outflows - Wholesale**
  - O.W.18 — Free Credits
- **Outflows - Deposits** *(forward start fields not provided)*
  - O.D.1 — Transactional Accounts
  - O.D.2 — Non-Transactional Relationship Accounts
  - O.D.3 — Non-Transactional Non-Relationship Accounts
  - O.D.4 — Operational Account Balances
  - O.D.5 — Excess Balances in Operational Accounts
  - O.D.6 — Non-Operational Account Balances
  - O.D.7 — Operational Escrow Accounts
  - O.D.8 — Non-Reciprocal Brokered Deposits
  - O.D.9 — Stable Affiliated Sweep Account Balances
  - O.D.10 — Less Stable Affiliated Sweep Account Balances
  - O.D.11 — Non-Affiliated Sweep Accounts
  - O.D.12 — Other Product Sweep Accounts
  - O.D.13 — Reciprocal Accounts
  - O.D.14 — Other Third-Party Deposits
  - O.D.15 — Other Accounts
- **Outflows - Other**
  - O.O.1 — Derivative Payables
  - O.O.2 — Collateral Called for Delivery
  - O.O.3 — TBA Purchases
  - O.O.4 — Credit Facilities
  - O.O.5 — Liquidity Facilities
  - O.O.6 — Retail Mortgage Commitments
  - O.O.7 — Trade Finance Instruments
  - O.O.8 — MTM Impact on Derivative Positions
  - O.O.9 — Loss of Rehypothecation Rights Due to a 1 Notch Downgrade
  - O.O.10 — Loss of Rehypothecation Rights Due to a 2 Notch Downgrade
  - O.O.11 — Loss of Rehypothecation Rights Due to a 3 Notch Downgrade
  - O.O.12 — Loss of Rehypothecation Rights Due to a Change in Financial Condition
  - O.O.13 — Total Collateral Required Due to a 1 Notch Downgrade
  - O.O.14 — Total Collateral Required Due to a 2 Notch Downgrade
  - O.O.15 — Total Collateral Required Due to a 3 Notch Downgrade
  - O.O.16 — Total Collateral Required Due to a Change in Financial Condition
  - O.O.17 — Excess Margin
  - O.O.18 — Unfunded Term Margin
  - O.O.19 — Interest and Dividends Payable
  - O.O.20 — Net 30-Day Derivative Payables
  - O.O.21 — Other Outflows Related to Structured Transactions
  - O.O.22 — Other Cash Outflows
- **Supplemental - Derivatives & Collateral**
  - S.DC.1 — Gross Derivative Asset Values
  - S.DC.2 — Gross Derivative Liability Values
  - S.DC.3 — Derivative Settlement Payments Delivered
  - S.DC.4 — Derivative Settlement Payments Received
  - S.DC.5 — Initial Margin Posted - House
  - S.DC.6 — Initial Margin Posted - Customer
  - S.DC.7 — Initial Margin Received
  - S.DC.8 — Variation Margin Posted - House
  - S.DC.9 — Variation Margin Posted - Customer
  - S.DC.10 — Variation Margin Received
  - S.DC.11 — Derivative CCP Default Fund Contribution
  - S.DC.12 — Other CCP Pledges and Contributions
  - S.DC.13 — Collateral Disputes Deliverables
  - S.DC.14 — Collateral Disputes Receivables
  - S.DC.15 — Sleeper Collateral Deliverables
  - S.DC.16 — Required Collateral Deliverables
  - S.DC.17 — Sleeper Collateral Receivables
  - S.DC.18 — Derivative Collateral Substitution Risk
  - S.DC.19 — Derivative Collateral Substitution Capacity
  - S.DC.20 — Other Collateral Substitution Risk
  - S.DC.21 — Other Collateral Substitution Capacity
- **Supplemental - Liquidity Risk Measurement**
  - S.L.1 — Subsidiary Liquidity That Cannot be Transferred
  - S.L.2 — Subsidiary Liquidity Available for Transfer
  - S.L.3 — Unencumbered Asset Hedges - Early Termination Outflows
  - S.L.4 — Non-Structured Debt Maturing in Greater than 30-days - Primary Market Maker
  - S.L.5 — Structured Debt Maturing in Greater than 30-days - Primary Market Maker
  - S.L.6 — Liquidity Coverage Ratio
  - S.L.7 — Subsidiary Funding That Cannot be Transferred
  - S.L.8 — Subsidiary Funding Available for Transfer
  - S.L.9 — Additional Funding Requirement for Off-Balance Sheet Rehypothecated Assets
  - S.L.10 — Net Stable Funding Ratio
- **Supplemental - Balance Sheet**[^1]
  - S.B.1 — Regulatory Capital Element
  - S.B.2 — Other Liabilities
  - S.B.3 — Non-Performing Assets
  - S.B.4 — Other Assets
  - S.B.5 — Counterparty Netting
  - S.B.6 — Carrying Value Adjustment
- **Supplemental - Informational**
  - S.I.1 — Long Market Value Client Assets
  - S.I.2 — Short Market Value Client Assets
  - S.I.3 — Gross Client Wires Received
  - S.I.4 — Gross Client Wires Paid
  - S.I.5 — FRB 23A Capacity
  - S.I.6 — Subsidiary Liquidity Not Transferrable

[^1]: The source PDF mislabels this section as "Supplemental - Informational"
    (a duplicate of the next heading). Its products all carry the `S.B.x`
    prefix and belong to the Supplemental - Balance Sheet table; the
    heading is corrected here. See `../../human-annotations.md` for
    details.
