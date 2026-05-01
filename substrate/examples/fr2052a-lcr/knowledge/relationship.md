# Relationship [Choice](../../specs/language/concepts/choice.md)

The Relationship type classifies whether a deposit counterparty has an
established banking relationship with the reporting institution. LCR
outflow rates distinguish deposits from established-relationship
customers (lower presumed runoff) from deposits without such a
relationship (higher presumed runoff).

## [Provenance](../../specs/language/concepts/provenance.md)

- [12 CFR §249.3 — Established relationship definition][cfr-3]

  > _Established relationship_ means a relationship between a retail
  > customer or counterparty and a covered company that is evidenced by
  > the retail customer or counterparty: (1) Actively using the covered
  > company to perform banking services; (2) Having at least one
  > additional banking relationship with the covered company at the
  > time the retail customer or counterparty opens a new account with
  > the covered company; or (3) Having any other relationship that is
  > documented by the covered company.

- [FR 2052a instructions, Product classifications for §O.D Outflows — Deposits][fr2052a-form]

  > Deposits are further classified by whether the counterparty has an
  > established relationship with the reporting institution, as defined
  > in 12 CFR §249.3.

## Variants

- **Established** — the counterparty has an established relationship
  with the reporting institution under 12 CFR §249.3.
- **None** — no established relationship.

## Type Class Instances

- **[Equality](../../specs/language/expressions/equality.md)** —
  inherited automatically from the [Choice][choice] concept.

[choice]: ../../specs/language/concepts/choice.md
[cfr-3]: https://www.ecfr.gov/current/title-12/part-249/section-249.3
[fr2052a-form]: https://www.federalreserve.gov/reportforms/forms/FR_2052a20220429_f.pdf
