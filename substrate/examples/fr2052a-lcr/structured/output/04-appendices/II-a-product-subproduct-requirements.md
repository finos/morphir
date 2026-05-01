# Appendix II-a: FR 2052a Product/Sub-Product Requirements

> This file is **hand-curated** with the help of human visual annotations
> recorded in [`../../human-annotations.md`](../../human-annotations.md).
> The splitter (`scripts/extract.py`) does not overwrite this file on re-run.

The following table displays which products require the reporting of a
Sub-Product or Sub-Product 2, along with the corresponding set of
acceptable values.

The original is laid out as five columns (Table, PID, Product, Sub-Product,
Sub-Product 2) broken across two pages. Here we collapse PID and Product
into a single cell because each row's PID/Product pairs travel together.
Sub-Product and Sub-Product 2 cells contain the full list of allowed
values for the row.

| Table | PID & Product | Sub-Product | Sub-Product 2 |
|---|---|---|---|
| Inflows - Assets | 2 — Capacity | Federal Reserve Bank<br>Swiss National Bank<br>Bank of England<br>European Central Bank<br>Bank of Japan<br>Reserve Bank of Australia<br>Bank of Canada<br>Other Central Bank<br>Federal Home Loan Bank<br>Other Government Sponsored Entity | — |
| Inflows - Assets | 3 — Unrestricted Reserve Balances<br>4 — Restricted Reserve Balances | Federal Reserve Bank<br>Swiss National Bank<br>Bank of England<br>European Central Bank<br>Bank of Japan<br>Reserve Bank of Australia<br>Bank of Canada<br>Other Central Bank<br>Currency and Coin | — |
| Inflows - Secured | 4 — Collateral Swaps | Level 1 Pledged<br>Level 2a Pledged<br>Level 2b Pledged<br>Non-HQLA Pledged<br>No Collateral Pledged | — |
| Outflows - Secured | 4 — Collateral Swaps | Level 1 Received<br>Level 2a Received<br>Level 2b Received<br>Non-HQLA Received<br>No Collateral Received | — |
| Outflows - Secured | 6 — Exceptional Central Bank Operations | Federal Reserve Bank<br>Swiss National Bank<br>Bank of England<br>European Central Bank<br>Bank of Japan<br>Reserve Bank of Australia<br>Bank of Canada<br>Other Central Bank<br>Covered Federal Reserve Facility Funding | — |
| Outflows - Secured | 7 — Customer Shorts<br>8 — Firm Shorts | External Cash Transactions<br>External Non-Cash Transactions<br>Firm Longs<br>Customer Longs<br>Unsettled - Regular Way<br>Unsettled - Forward | — |
| Outflows - Secured | 9 — Synthetic Customer Shorts<br>10 — Synthetic Firm Financing | Firm Short<br>Synthetic Customer Long<br>Synthetic Firm Sourcing<br>Futures<br>Other<br>Unhedged | — |
| Inflows - Secured | 9 — Synthetic Customer Longs<br>10 — Synthetic Firm Sourcing | Physical Long Position<br>Synthetic Customer Short<br>Synthetic Firm Financing<br>Futures<br>Other<br>Unhedged | — |
| Supplemental — Derivatives & Collateral | 1 — Gross Derivative Asset Values<br>2 — Gross Derivative Liability Values<br>3 — Derivative Settlement Payments Delivered<br>4 — Derivative Settlement Payments Received<br>5 — Initial Margin Posted - House<br>6 — Initial Margin Posted - Customer<br>7 — Initial Margin Received<br>8 — Variation Margin Posted - House<br>9 — Variation Margin Posted - Customer<br>10 — Variation Margin Received | Rehypothecateable Collateral Unencumbered<br>Rehypothecateable Collateral Encumbered<br>Non-Rehypothecateable Collateral<br>Segregated Cash<br>Non-Segregated Cash | OTC - Bilateral<br>OTC - Centralized (Principal)<br>OTC - Centralized (Agent)<br>Exchange-traded (Principal)<br>Exchange-traded (Agent) |
