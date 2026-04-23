# Transactional Accounts [Record](../../specs/language/concepts/record.md)

The Transactional Accounts record captures one row of FR 2052a section
**§O.D.1 Outflows — Deposits — Transactional Accounts**. Each row
represents an aggregated deposit position classified by counterparty,
account type, relationship, maturity, and insurance status. A single
submission contains many such rows.

The fields here are a minimal subset sufficient to drive the retail
outflow calculation. The full FR 2052a schema additionally carries
currency, collateral class, encumbrance flags, and reporting-entity
identifiers; those are orthogonal to the classification logic and are
omitted in this MVP slice.

## [Provenance](../../specs/language/concepts/provenance.md)

- [FR 2052a instructions, §O.D.1 Transactional Accounts][fr2052a-form]

  > Transactional Accounts captures deposit balances held in
  > transactional accounts, classified by counterparty type, insurance
  > status, established relationship, and remaining maturity. The
  > reported amount is the unpaid principal balance as of the reporting
  > date.

- [12 CFR §249.32(a) — Retail funding outflow amount][cfr-32a]

  > A covered company shall calculate its retail funding outflow amount
  > as the sum of outflow amounts for each category of retail deposit,
  > applying the applicable outflow rate to the outstanding balance.

## Fields

| Name              | Type                                                   | Optionality | Description                                                            |
| ----------------- | ------------------------------------------------------ | ----------- | ---------------------------------------------------------------------- |
| `report_date`     | [Date](../../specs/language/expressions/date.md)       | required    | The FR 2052a reporting date as of which balances are measured.         |
| `amount`          | [Decimal](../../specs/language/expressions/decimal.md) | required    | Unpaid principal balance, in reporting currency units.                 |
| `counterparty`    | [Counterparty](counterparty.md)                        | required    | The party on the other side of the deposit position.                   |
| `account_type`    | [Account Type](account-type.md)                        | required    | Whether the deposit is held in a transactional account.                |
| `relationship`    | [Relationship](relationship.md)                        | required    | Whether the counterparty has an established relationship.              |
| `maturity_bucket` | [Maturity Bucket](maturity-bucket.md)                  | required    | Remaining contractual maturity, bucketed.                              |
| `insured`         | [Boolean](../../specs/language/expressions/boolean.md) | required    | `true` when the deposit is covered by deposit insurance up to limit.   |

## Type Class Instances

Transactional Accounts does not declare an [Equality][eq] instance.
Rows are identified by the submission they belong to and their
position within it, not by structural equality of their fields; two
rows with identical field values may represent distinct aggregated
populations.

[eq]: ../../specs/language/expressions/equality.md
[cfr-32a]: https://www.ecfr.gov/current/title-12/part-249/section-249.32#p-249.32(a)
[fr2052a-form]: https://www.federalreserve.gov/reportforms/forms/FR_2052a20220429_f.pdf
