# Retail Outflow

Computes the total retail deposit outflow in dollars from a collection
of FR 2052a §O.D.1 [Transactional Accounts](transactional-accounts.md)
rows. This is the retail-deposit contribution to the LCR denominator;
the full LCR ratio composes this with other outflow categories and
with inflows and HQLA, which are out of scope for this example.

The calculation has two steps:

1. For each row, look up the applicable outflow rate using the
   [Retail Outflow Rate](retail-outflow-rate.md) decision table, then
   multiply by the row's `amount` to produce a per-row outflow.
2. Sum the per-row outflows across the collection.

## [Provenance](../../specs/language/concepts/provenance.md)

- [12 CFR §249.32(a) — Retail deposit outflow amount][cfr-32a]

  > A covered company shall calculate its retail deposit outflow amount
  > as the sum of the outflow amounts for each category of retail
  > deposit, each calculated by multiplying the outstanding balance by
  > the applicable outflow rate.

## Inputs

- `deposits` — a [Collection][col] of
  [Transactional Accounts](transactional-accounts.md) rows representing
  the retail-deposit population for one reporting date.

## Definitions

### `row_outflow`

The dollar outflow for a single deposit row. Defined as a
[per-row](transactional-accounts.md) function applied by
[Map][map]: the rate is looked up via the
[Retail Outflow Rate][rate] decision table using the row's
classification fields, then multiplied by the row's `amount`.

- [Multiply][mul]
  - [Retail Outflow Rate][rate]
    - `row.counterparty`
    - `row.insured`
    - `row.account_type`
    - `row.relationship`
  - `row.amount`

#### Test cases

| `row`                                                                                                                           | `row_outflow` |
| ------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| `{ amount: 1000, counterparty: Retail, insured: true, account_type: Transactional, relationship: Established, ... }`            | 30            |
| `{ amount: 1000, counterparty: Retail, insured: true, account_type: Non-Transactional, relationship: None, ... }`               | 100           |
| `{ amount: 2500, counterparty: Retail, insured: false, account_type: Transactional, relationship: Established, ... }`           | 250           |
| `{ amount: 500, counterparty: Small Business, insured: true, account_type: Non-Transactional, relationship: Established, ... }` | 15            |

### `per_row_outflows`

The collection of per-row outflows, one element per input row.

- [Map][map]
  - `deposits`
  - `row_outflow`

### `total_outflow`

The total retail outflow for the reporting date: the sum of per-row
outflows.

- [Sum][sum]
  - `per_row_outflows`

#### Test cases

| `deposits`                                                                                                                                                                              | `total_outflow` |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `[]`                                                                                                                                                                                    | 0               |
| `[{ amount: 1000, Retail, insured, Transactional, Established }]`                                                                                                                       | 30              |
| `[{ amount: 1000, Retail, insured, Transactional, Established }, { amount: 1000, Retail, insured, Non-Transactional, None }]`                                                           | 130             |
| `[{ amount: 2500, Retail, uninsured, Transactional, Established }, { amount: 500, Small Business, insured, Non-Transactional, Established }]`                                           | 265             |

[col]: ../../specs/language/expressions/collection.md
[cfr-32a]: https://www.ecfr.gov/current/title-12/part-249/section-249.32#p-249.32(a)
[map]: ../../specs/language/expressions/collection.md#map-operation
[mul]: ../../specs/language/expressions/number.md#multiplication-operation
[rate]: retail-outflow-rate.md
[sum]: ../../specs/language/expressions/collection.md#sum-operation
