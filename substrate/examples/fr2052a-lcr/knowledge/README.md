# FR 2052a / LCR Example

This example demonstrates how to codify a banking regulation as an
executable substrate specification. It covers a narrow but complete slice
of two related artifacts:

- **FR 2052a** — the Federal Reserve's _Complex Institution Liquidity
  Monitoring Report_, a data-collection form that large U.S. banks
  submit daily or monthly. FR 2052a defines a schema: what counts as a
  deposit row, what fields it carries, what categorical values are
  allowed.
- **The Liquidity Coverage Ratio (LCR) rule** — codified at
  [12 CFR Part 249][part-249], which specifies the runoff rates applied
  to each category of liability and the calculation that produces the
  LCR itself. The two are inseparable in practice: FR 2052a is the data
  feed; 12 CFR §249 is the calculation.

## Scope

The example covers one FR 2052a section, one LCR rate assignment, and
the computation that combines them:

- **FR 2052a §O.D.1 Transactional Accounts** — a [Record][rec]
  describing one deposit row.
- **Supporting categorical types** — [Counterparty](counterparty.md),
  [Account Type](account-type.md), [Relationship](relationship.md), and
  [Maturity Bucket](maturity-bucket.md), each declared as a
  [Choice][choice]. Maturity Bucket is the data-carrying case; the rest
  are pure enumerations.
- **Retail outflow rate** — a [Decision Table][dt] encoding the rate
  assignment from [12 CFR §249.32(a)][cfr-32a].
- **Total retail outflow** — a user module computing the dollar outflow
  from a collection of deposit rows, combining classification and
  rates.

Deliberately out of scope in this MVP slice:

- Other FR 2052a sections (O.D.2 through O.D.13, outflows other than
  deposits, all inflows, HQLA composition, supplemental reporting).
- The full LCR ratio: numerator (HQLA), denominator (net cash
  outflows), and the 75% inflow cap.
- Transition-window amendments and historical version selection —
  the example targets a single authoritative corpus version.

Extending to those cases is copy-paste of the patterns shown here.

## How to read

Start at the data schema, work up to the rule, then the calculation:

1. [Counterparty](counterparty.md), [Account Type](account-type.md),
   [Relationship](relationship.md) — categorical dimensions used by
   every retail deposit row.
2. [Maturity Bucket](maturity-bucket.md) — demonstrates a
   data-carrying [Choice][choice] (variants parameterised by day
   ranges).
3. [Transactional Accounts](transactional-accounts.md) — the FR 2052a
   §O.D.1 record schema.
4. [Retail Outflow Rate](retail-outflow-rate.md) — the
   [Decision Table][dt] assigning a rate to each classification.
5. [Retail Outflow](retail-outflow.md) — the user module computing
   dollar outflow over a collection of deposits.

## Conventions

- Every artifact derived from an external document carries a
  [Provenance][prov] section citing the form or regulation.
  Normative passages are quoted verbatim as blockquotes.
- Categorical values use [Choice][choice] rather than [String][str]:
  the allowed set is fixed by the regulation and enforced statically.
- Rate assignments use [Decision Tables][dt] rather than nested
  [If-Then-Else][ite]: the rule is tabular in the regulation and
  should remain tabular in the specification.
- Optional fields use the [Optionality][opt] convention: the slot is
  marked optional and consumers coalesce explicitly with
  [Default][opt-default].
- Cross-references to substrate concepts use reference-style link
  definitions to keep inline prose readable.

[choice]: ../../specs/language/concepts/choice.md
[cfr-32a]: https://www.ecfr.gov/current/title-12/part-249/section-249.32#p-249.32(a)
[dt]: ../../specs/language/concepts/decision-table.md
[ite]: ../../specs/language/expressions/boolean.md#if-then-else-operation
[opt]: ../../specs/language/concepts/optionality.md
[opt-default]: ../../specs/language/concepts/optionality.md#default-operation
[part-249]: https://www.ecfr.gov/current/title-12/part-249
[prov]: ../../specs/language/concepts/provenance.md
[rec]: ../../specs/language/concepts/record.md
[str]: ../../specs/language/expressions/string.md
