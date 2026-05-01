# Maturity Bucket [Choice](../../specs/language/concepts/choice.md)

The Maturity Bucket type classifies a position by the number of days
remaining to contractual maturity. FR 2052a reports maturity as a
bucketed value rather than a raw date so that positions with comparable
runoff horizons aggregate naturally.

Unlike the other categorical dimensions in this example, Maturity
Bucket carries data: a bucket is either _Open_ (no contractual
maturity), a contiguous day _Range_, or _Beyond_ a threshold. The
bounds are parameters of the variant rather than names of distinct
variants, because the LCR rule references the numeric thresholds
directly (e.g. "within 30 days").

## [Provenance](../../specs/language/concepts/provenance.md)

- [FR 2052a instructions, Field Definitions — Maturity Bucket][fr2052a-form]

  > Maturity Bucket reflects the remaining contractual maturity of the
  > reported position, measured in calendar days from the reporting
  > date. Positions without a contractual maturity are reported as
  > Open.

- [12 CFR §249.32 — Outflow horizon][cfr-32]

  > Outflow amounts are calculated over a prospective 30 calendar-day
  > period beginning on the calculation date.

## Variants

- **Open** — no contractual maturity (e.g. demand deposits).
- **Range** — a contiguous, inclusive range of days to maturity.
  - `from_days` — [Integer](../../specs/language/expressions/integer.md),
    required. Lower bound, inclusive.
  - `to_days` — [Integer](../../specs/language/expressions/integer.md),
    required. Upper bound, inclusive.
- **Beyond** — longer than a threshold number of days.
  - `from_days` — [Integer](../../specs/language/expressions/integer.md),
    required. Lower bound, exclusive.

## Type Class Instances

- **[Equality](../../specs/language/expressions/equality.md)** —
  inherited automatically from the [Choice][choice] concept: two values
  are equal when they are the same variant and their `from_days` and
  `to_days` fields are equal.
- **[Ordering](../../specs/language/expressions/ordering.md)** — not
  implemented. A meaningful order would require comparing open-ended
  and bounded variants against each other, which the LCR rule does not
  require. Consumers that need to ask "does this bucket intersect the
  next 30 days?" should use [Match][match] on the variants directly.

[choice]: ../../specs/language/concepts/choice.md
[match]: ../../specs/language/concepts/choice.md#match-operation
[cfr-32]: https://www.ecfr.gov/current/title-12/part-249/section-249.32
[fr2052a-form]: https://www.federalreserve.gov/reportforms/forms/FR_2052a20220429_f.pdf
