# Retail Outflow Rate [Decision Table](../../specs/language/concepts/decision-table.md)

The Retail Outflow Rate decision table assigns an LCR runoff rate to a
retail deposit position based on its classification. The rates and
conditions are fixed by [12 CFR §249.32(a)][cfr-32a].

Two concepts from the rule drive the rates:

- **Stable** retail deposits are deposits entirely covered by deposit
  insurance AND either held in a transactional account OR from a
  depositor with an established relationship. Stable deposits receive
  the lowest runoff rate (3%).
- **Less stable** retail deposits are insured retail deposits that do
  not qualify as stable, plus uninsured retail deposits. Less stable
  deposits receive a 10% runoff rate.

Small Business counterparties are treated identically to natural-person
Retail counterparties for this rate, per [§249.32(a)(5)][cfr-32a-5].
Non-retail counterparties fall outside §249.32(a) and are not in scope
for this table.

## [Provenance](../../specs/language/concepts/provenance.md)

- [12 CFR §249.32(a) — Retail deposit outflow amount][cfr-32a]

  > A covered company shall calculate its retail deposit outflow amount
  > as follows: (1) 3 percent of all stable retail deposits; (2) 10
  > percent of all other retail deposits that are not brokered deposits;
  > ...

- [12 CFR §249.3 — Stable retail deposit definition][cfr-3]

  > _Stable retail deposit_ means a retail deposit that is entirely
  > covered by deposit insurance and: (1) Is held by the depositor in
  > a transactional account; or (2) The depositor that holds the
  > account has another established relationship with the covered
  > company such as another deposit account, a loan, bill payment
  > services, or any similar service or product provided to the
  > depositor that the covered company demonstrates to the satisfaction
  > of the Board would make deposit withdrawal highly unlikely during
  > a liquidity stress event.

## Inputs

- `counterparty` — [Counterparty](counterparty.md)
- `insured` — [Boolean](../../specs/language/expressions/boolean.md)
- `account_type` — [Account Type](account-type.md)
- `relationship` — [Relationship](relationship.md)

## Outputs

- `outflow_rate` — [Decimal](../../specs/language/expressions/decimal.md)

## Rules

| counterparty   | insured | account_type      | relationship | → outflow_rate |
| -------------- | ------- | ----------------- | ------------ | -------------- |
| Retail         | true    | Transactional     |              | 0.03           |
| Retail         | true    | Non-Transactional | Established  | 0.03           |
| Retail         | true    | Non-Transactional | None         | 0.10           |
| Retail         | false   |                   |              | 0.10           |
| Small Business | true    | Transactional     |              | 0.03           |
| Small Business | true    | Non-Transactional | Established  | 0.03           |
| Small Business | true    | Non-Transactional | None         | 0.10           |
| Small Business | false   |                   |              | 0.10           |

The table is exhaustive over the in-scope counterparties: the four
Retail rows and four Small Business rows cover every combination of
`insured`, `account_type`, and `relationship`. Positions whose
counterparty is Non-Financial Corporate or Bank are out of scope for
this table and are routed to a different rate table (not modelled in
this MVP slice); evaluating this table for such a row is a
specification error at the call site, not a runtime fallthrough.

[cfr-3]: https://www.ecfr.gov/current/title-12/part-249/section-249.3
[cfr-32a]: https://www.ecfr.gov/current/title-12/part-249/section-249.32#p-249.32(a)
[cfr-32a-5]: https://www.ecfr.gov/current/title-12/part-249/section-249.32#p-249.32(a)(5)
