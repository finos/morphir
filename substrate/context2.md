# Choice

## Summary

A Choice is a type whose members are partitioned into a fixed set of
named **variants**. Every value is exactly one variant. A variant may
carry zero or more typed fields; the fields of different variants are
independent. Variant names are unique within a Choice. A Choice with
only zero-field variants is an enumeration. A declaration is identified
by a heading whose text links to this concept page, e.g.
`### Maturity Bucket [Choice](choice.md)`. Every Choice supports the
meta-operations **Construct**, **Is Variant**, and **Match** (which is
exhaustive).

# Provenance

## Summary

A Provenance section records the authoritative external sources from
which a specification artifact derives — regulations, standards,
statutes, published guidance. Any artifact (a Record type, a Choice, a
Decision Table, an Operation, or a whole module) that encodes material
from an external document should declare its sources. A provenance
section is identified by a heading whose text links to this concept
page, e.g. `#### [Provenance](../concepts/provenance.md)`. Its scope is
the enclosing heading. Sources are listed as a bulleted list with
deep links and optional verbatim quoted passages from the source.

# Type Class

## Summary

A type class defines a shared interface: a set of operations that any
type may implement. A type that implements a type class is said to
*instance* it. Each operation is marked **Required** (every instancing
type must implement it) or **Derived** (default definition in terms of
required operations; may be overridden). A type class may extend other
type classes — an instance of the extending class must also instance
each extended class. Some type class modules also list known member
types in a **Type Class Members** section as a quick cross-reference.

# Equality [Type Class](#type-class)

## Summary

The Equality type class defines operations for comparing values to
determine if they are equal or not equal. It applies to types where
equality is meaningful. Operations: **Equal** (required) and **Not
Equal** (derived as `NOT (a == b)`). All operations return Boolean.

# Account Type [Choice](#choice)

The Account Type classifies whether a deposit is held in a transactional
account. The distinction is material for LCR: transactional accounts are
presumed to be operational and receive a lower outflow rate.

## [Provenance](#provenance)

* [FR 2052a instructions, Product classifications for §O.D Outflows — Deposits][fr2052a-form]

  > The distinction between transactional and non-transactional accounts
  > follows Regulation D. Transactional accounts are deposits from which
  > the depositor is permitted to make transfers or withdrawals by
  > negotiable instrument, payment order, debit card, or similar means.

* [12 CFR §249.3 — Transactional account definition][cfr-3]

  > For purposes of this part, a transactional account has the meaning
  > given to "transaction account" in Regulation D (12 CFR part 204),
  > §204.2(e).

## Variants

* **Transactional** — a deposit account from which withdrawals or
  transfers may be made by negotiable instrument, payment order, debit
  card, or similar means (per Regulation D §204.2(e)).
* **Non-Transactional** — a deposit account from which such withdrawals
  are limited or not permitted (savings accounts, time deposits, etc.).

## Type Class Instances

* **[Equality](#equality-type-class)** —
  inherited automatically from the [Choice][choice] concept.

[choice]: #choice

[cfr-3]: https://www.ecfr.gov/current/title-12/part-249/section-249.3

[fr2052a-form]: https://www.federalreserve.gov/reportforms/forms/FR_2052a20220429_f.pdf
