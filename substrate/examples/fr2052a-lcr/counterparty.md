# Counterparty [Choice](../../specs/language/concepts/choice.md)

The Counterparty type classifies the party on the other side of a
position for FR 2052a reporting. The set of counterparty categories is
fixed by the form instructions; each row of the report is labelled with
exactly one counterparty.

This example declares a subset of the full counterparty enumeration
sufficient to demonstrate retail outflow classification. The full set
published in the FR 2052a instructions additionally includes Sovereign,
Central Bank, GSE, PSE, MDB, Other Supranational, Pension Fund,
Broker-Dealer, Investment Company or Advisor, Financial Market Utility,
Other Supervised Non-Bank Financial Entity, Non-Regulated Fund, and
Internal.

## [Provenance](../../specs/language/concepts/provenance.md)

- [FR 2052a instructions, Field Definitions — Counterparty (version 2025-02-26)][fr2052a-form]

  > Counterparty refers to the entity that is the other party to the
  > transaction. The table below indicates the appropriate counterparty
  > classification for each reported row.

- [12 CFR §249.3 — Definition of retail customer or counterparty][cfr-3]

  > _Retail customer or counterparty_ means a customer or counterparty
  > that is: (1) An individual; (2) A business customer that meets the
  > definition of a retail customer or counterparty under §249.3; or
  > (3) A living or testamentary trust that: (i) Is solely for the
  > benefit of natural persons; (ii) Does not have a corporate trustee;
  > and (iii) Terminates within 21 years and 10 months after the death
  > of grantors or beneficiaries of the trust living on the effective
  > date of the trust or within 25 years after the effective date of
  > the trust.

## Variants

- **Retail** — a natural-person customer.
- **Small Business** — a business customer meeting the FR 2052a
  definition of a small business counterparty (treated as retail-like
  for outflow classification).
- **Non-Financial Corporate** — a non-financial business entity that
  is not a small business.
- **Bank** — a depository institution counterparty.

## Type Class Instances

- **[Equality](../../specs/language/expressions/equality.md)** —
  inherited automatically from the [Choice][choice] concept: two values
  are equal when they name the same variant.
- **[Ordering](../../specs/language/expressions/ordering.md)** — not
  implemented. Counterparty categories have no canonical order.

[choice]: ../../specs/language/concepts/choice.md
[cfr-3]: https://www.ecfr.gov/current/title-12/part-249/section-249.3
[fr2052a-form]: https://www.federalreserve.gov/reportforms/forms/FR_2052a20220429_f.pdf
