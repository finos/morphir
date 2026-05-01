# Account Type [Choice](../../specs/language/concepts/choice.md)

The Account Type classifies whether a deposit is held in a transactional
account. The distinction is material for LCR: transactional accounts are
presumed to be operational and receive a lower outflow rate.

## [Provenance](../../specs/language/concepts/provenance.md)

- [FR 2052a instructions, Product classifications for §O.D Outflows — Deposits][fr2052a-form]

  > The distinction between transactional and non-transactional accounts
  > follows Regulation D. Transactional accounts are deposits from which
  > the depositor is permitted to make transfers or withdrawals by
  > negotiable instrument, payment order, debit card, or similar means.

- [12 CFR §249.3 — Transactional account definition][cfr-3]

  > For purposes of this part, a transactional account has the meaning
  > given to "transaction account" in Regulation D (12 CFR part 204),
  > §204.2(e).

## Variants

- **Transactional** — a deposit account from which withdrawals or
  transfers may be made by negotiable instrument, payment order, debit
  card, or similar means (per Regulation D §204.2(e)).
- **Non-Transactional** — a deposit account from which such withdrawals
  are limited or not permitted (savings accounts, time deposits, etc.).

## Type Class Instances

- **[Equality](../../specs/language/expressions/equality.md)** —
  inherited automatically from the [Choice][choice] concept.

[choice]: ../../specs/language/concepts/choice.md
[cfr-3]: https://www.ecfr.gov/current/title-12/part-249/section-249.3
[fr2052a-form]: https://www.federalreserve.gov/reportforms/forms/FR_2052a20220429_f.pdf
