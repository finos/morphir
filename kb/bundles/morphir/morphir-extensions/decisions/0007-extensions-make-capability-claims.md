---
type: Decision Record
title: Extensions make capability claims
state: Accepted
decided: 2026-09-24
tags: [extensions, capabilities, mep, distribution, compatibility, naming]
status: stable
description: The document an extension authors about itself is a capability claim set made of claims, not a capability statement; the version-2 draft formats rename their members and move to the next draft, and readers still accept the draft.1 spelling.
sources:
  - id: spec
    resource: https://github.com/finos/morphir/discussions/921
    title: "finos/morphir#921: capability statements across the extension lifecycle (working spec)"
---

# Extensions make capability claims

The document an extension authors about its own capabilities is a **capability claim set**. Each entry in
it is a **claim**. The host checks the claims: at install it probes the selected artifact, and it refuses
the install when the probe disagrees with the claims. Decisions
[0003](/decisions/0003-the-guest-authors-its-capability-statement.md),
[0004](/decisions/0004-readers-ignore-unknown-members-unless-critical.md) and
[0006](/decisions/0006-the-describe-fallback-reports-only-what-a-session-reports.md) call this document a
capability statement. Their substance still holds. This decision replaces only their vocabulary and the
wire names that follow from it. It does not supersede them.

## Summary

| Where | draft.1 | draft.2 |
| --- | --- | --- |
| Document version member | `statementVersion`: `0.1.0-draft.1` | `claimsVersion`: `0.1.0-draft.2` |
| Member that holds the document in a bundle descriptor artifact, an index artifact record and an installed catalog record | `statement` | `claims` |
| How the host checked it | `statementSource`: `declared`, `probed` | `claimCheck`: `unchecked`, `probed` |
| Critical-path prefix | `statement.` | `claims.` |
| `schemaVersion` of the version-2 descriptor, index record and catalog | `2.0.0-draft.1` | `2.0.0-draft.2` |

`probeSource` (`describe`, `session-fallback`), the document's other members, the method
`morphir.extension.describe`, the MEP version `0.1` and the version-1 formats do not change.

| Option | Outcome | Why |
| --- | --- | --- |
| Rename to capability claims now, before any extension publishes a version-2 descriptor | Chosen | The name says what the document is, and the renamed formats are still drafts |
| Keep "capability statement" | Rejected | "Statement" does not say that an author stands behind it or that the host checks it |
| Rename after extensions adopt version 2 | Rejected | Every first-party bundle would publish the old names and then change them |
| Keep draft.1 and alias the new names inside it | Rejected | A draft matches only exactly, so the same version cannot have two spellings |

## Why

A claim is an assertion that its author stands behind and that a reader can check. That is how the host
treats the document. The extension claims what it can do, the host probes the artifact, and install fails
when the two disagree. The same word has this meaning in JWT, OpenID Connect and Verifiable Credentials,
where an issuer makes claims and a relying party verifies them. "Statement" is neutral. It also made the
provenance member read badly: a record said `statementSource: probed`, but a probe does not produce a
statement. The record keeps the claims the extension made and says how the host checked them.

The timing matters. Hosts `0.4.0-beta.5` and `0.4.0-beta.6` shipped the draft.1 formats, but no extension
publishes a version-2 descriptor yet. The next planned work has every first-party bundle publish one.
Renaming first means the old names never reach a bundle.

## Compatibility

The formats are drafts, and under the repository's SemVer rules a draft matches only exactly. The renamed
formats therefore take the next draft number:

- Writers emit only draft.2. This covers the SDK's `describe` response and the index records and catalogs
  the host writes.
- Readers accept draft.2 and draft.1. A draft.1 record, or a draft.1 document from an older guest, is read
  and converted. `declared` becomes `unchecked`, and a `statement.` critical path becomes `claims.`. Hosts
  `0.4.0-beta.5` and `0.4.0-beta.6` wrote draft.1 records into Morphir homes and index repositories, and
  those keep loading.
- A record that mixes draft.1 and draft.2 names or versions is refused.
- Hosts `0.4.0-beta.6` and earlier cannot read draft.2. A Morphir home that a newer host wrote version-2
  records into is not readable by those hosts. Drafts promise no compatibility with each other, so this
  is accepted.

## Revisit when

The first released version, `1.0.0` of the claim set or a released `2.0.0` of the records, removes the
draft.1 reader. A later rename then takes a new major.
