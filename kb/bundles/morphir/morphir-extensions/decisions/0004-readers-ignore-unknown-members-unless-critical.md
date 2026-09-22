---
type: Decision Record
title: Readers ignore unknown members unless critical
state: Accepted
decided: 2026-09-22
tags: [extensions, capabilities, mep, distribution, release, compatibility]
status: stable
description: Every reader of extension formats ignores unknown members unless they are marked critical, accepts schema N and N-1, and converts old records, so host and extension changes ship on their own after one bootstrap host release.
sources:
  - id: spec
    resource: https://github.com/finos/morphir/discussions/921
    title: "finos/morphir#921: capability statements across the extension lifecycle (working spec)"
  - id: single-file-thread
    resource: https://github.com/finos/morphir/discussions/915
    title: "finos/morphir#915: a single file is a synthesized project (working thread)"
  - id: single-file-spec
    resource: https://github.com/finos/morphir/discussions/917
    title: "finos/morphir#917: a single file is a synthesized project (spec)"
  - id: protocol
    resource: https://github.com/finos/morphir/blob/fb7586230dfe6d8d8472bde21a0ea0af72646498/docs/design/draft/extensions/protocol.md
    title: Morphir Extension Protocol (draft)
---

# Readers ignore unknown members unless critical

Every reader of an extension format ignores a member it does not understand, unless the member is
marked critical. Readers accept a range of schema versions, convert old records, and fall back when a
guest lacks `describe`. With these rules, a host change and an extension change each ship on their own.
One bootstrap host release comes first. These are decisions 6 to 11 of finos/morphir#921 (source
`spec`):

| # | Decision |
| --- | --- |
| 6 | Readers ignore unknown members unless they are marked critical, at every boundary. |
| 7 | Formats carry a schema version, and readers accept a range: `N` and `N-1`. |
| 8 | An extension may state the minimum host it needs, as a critical member (`requires.host`). |
| 9 | `morphir.extension.describe` is optional for guests. A host falls back to `initialize`, `capabilities`, `shutdown`. |
| 10 | A record without a statement is converted, not refused. The host builds a statement from the old flat keys and marks it `declared` rather than `probed`. |
| 11 | There are three release paths: host only, extension only, and both (host first, then extension). One bootstrap host release is unavoidable. |

[Capability statements across the extension lifecycle](/design/capability-statements.md) is the
narrative home. Decision [0003](/decisions/0003-the-guest-authors-its-capability-statement.md) records
the statement itself and how each phase handles it.

## Summary

Before this decision, every host parser for the bundle descriptor, the index record and the installed
catalog used `deny_unknown_fields`. A released CLI rejected any new key until a new CLI shipped, so an
extension could not adopt a new capability on its own. The `TRANSITIONAL_FIELDS` skip in the
`test:cli-release` task existed to work around that in tests (source `spec`). The MEP draft already
told receivers to ignore unknown fields in protocol messages (source `protocol`); the distribution
formats did the opposite. The decision applies one rule at every boundary and gives each kind of old
input a defined path.

The first five rows are the rules #921 adopts. The rejected rows are the alternatives each rule
replaces; #921 does not list them in its rejected-alternatives table, so this record states them from
the rules themselves.

| Option | Outcome | Why |
| --- | --- | --- |
| Must-ignore unless critical, at every boundary | Chosen | Old readers accept new optional members, and still refuse a change of meaning |
| Schema ranges `N` and `N-1` | Chosen | A new host reads the formats that released extensions still write |
| `requires.host` as a critical member | Chosen | An extension that needs a newer host says so, and an older host refuses with a clear message |
| `describe` optional, with a session fallback | Chosen | Released guests without `describe` keep working |
| Convert old records and mark them `declared` | Chosen | Installed extensions keep working, and the record shows it was never probed |
| Three release paths and one bootstrap host release | Chosen | Most changes ship on one side; only a critical change needs both |
| Strict parsers, with new keys skipped in tests | Rejected | Every new key needs a CLI release before any extension can use it |
| Readers accept only the current schema | Rejected | A new host would reject every descriptor and record already published |
| Require `describe` in every guest | Rejected | Every released guest would fail publish and install |
| Refuse records without a statement | Rejected | Every installed extension would stop working on upgrade |
| Release host and extension changes together | Rejected | Neither side has a released partner to test against |

## Why

Decision numbers below follow the table above. The narrative home numbers decisions 6 to 10 as
compatibility rules 1 to 5, as #921 does.

Decision 6 is the core. A reader ignores an optional member it does not understand, and refuses a member
listed in `critical` that it does not understand. The boundaries are the bundle descriptor, the index
record, the installed record, the capability statement and the `describe` result. An author who adds an
optional member needs no host release. An author who changes meaning marks the path critical, and an
old reader refuses by name instead of guessing. Capability kinds stay strict, as decision
[0003](/decisions/0003-the-guest-authors-its-capability-statement.md) and #921 describe: a kind a reader
does not know is an error.

Decision 7 covers changes that must-ignore cannot absorb, such as a renamed or restructured member. A host
reads schema `N` and `N-1` of each format. A publisher writes the highest schema that the oldest host it
targets can read. One step of overlap gives each side one release to catch up. Whether one step is
enough is judged, not measured.

Decision 8 gives an extension a way to depend on a host feature. `requires.host` is a semver range over the
host version. Because the extension lists it in `critical`, a host too old to know the member refuses
instead of ignoring it. A host outside the range refuses with a message that names the range.

Decision 9 keeps released guests working. A guest without `describe` answers `-32601`, or refuses because
the request came before `initialize`. The host then runs `initialize`, `morphir.extension.capabilities`,
`shutdown` and `exit`, and reads the same information from that session.

Decision 10 keeps installed extensions working. A record written before statements existed has only flat
keys. The host builds a statement from them and marks it `declared`, so a reader can tell it from a
`probed` statement. Install and the first session then verify it as usual. The morphir-elm branch
`feat/mep-workspace-discovery`, which writes `workspaceDiscovery: true` as a flat key, relies on this
decision: its key is correct under schema 1, and the bootstrap host converts it.

Decision 11 follows from the others. A host-only release must read every supported older descriptor,
record and guest. Its gate is a host compatibility suite: the new CLI publishes, installs and compiles
with the latest released bundle of each first-party extension. An extension-only release must work with
the released host it targets, or state `requires.host`. Its gate is `test:cli-release` against the
pinned CLI, extended to the Elm process bundle. A change that needs both goes host first: the host suite
passes, the host releases, the extension pin moves, and then `test:cli-release` passes. Only a critical
change needs that path.

Released hosts follow none of these rules, which is why one bootstrap host release is unavoidable. It is
a host-only release that implements decisions 6 to 10 and still reads schema-1 descriptors and
records. Until it ships, extensions keep writing the flat schema-1 keys. After it ships and the pins
move, extensions adopt statements and schema 2.

The bootstrap release also meets the removal condition of three transitional mechanisms from
finos/morphir#915 (source `single-file-thread`): the legacy compile envelope in the Rust SDK,
`compile_wire_request` in the CLI, and the `TRANSITIONAL_FIELDS` skip. All three retire when the pins
move. The bootstrap host is the release that carries steps 5 and 6 of finos/morphir#917 (source
`single-file-spec`).

## Alternatives rejected

### Strict parsers, with new keys skipped in tests

This was the existing practice. `deny_unknown_fields` makes every new key a breaking change for released
CLIs, and `TRANSITIONAL_FIELDS` only hides that in one test task. Every capability still needs a CLI
release before any extension can use it.

### Readers accept only the current schema

A host that reads only the newest schema rejects every descriptor and record that released extensions
have already published. Each schema change would then force every extension to re-release at once.

### Require `describe` in every guest

Every guest released before `describe` existed would fail publish and install until it re-released.
The session fallback gives the same information at a higher cost, so nothing is lost by making
`describe` optional.

### Refuse records without a statement

Every extension installed before statements existed would stop working when the user upgraded the host.
Conversion keeps them working, and the `declared` mark keeps the difference visible.

### Release host and extension changes together

If both sides change at once, neither has a released partner to test against. The "Both" path orders
them instead: host first, then the extension, with a gate between.

## Consequences

- Every host parser for the bundle descriptor, the index record and the installed catalog drops
  `deny_unknown_fields` in favor of must-ignore with a `critical` list. Each format gains a schema
  version.
- The next host release is the bootstrap release. It implements the rules, reads schema 1, and retires
  the legacy compile envelope, `compile_wire_request` and the `TRANSITIONAL_FIELDS` skip once the pins
  move.
- Extensions keep writing flat schema-1 keys until the bootstrap host ships and the pins move.
- A host compatibility suite becomes the gate for host-only releases. `test:cli-release` grows to cover
  the Elm process bundle.
- A statement is either `probed` or `declared`, and readers can tell which.

## Revisit when

Revisit the `N`/`N-1` range if a format needs to change twice within one host release cycle, since one
step of overlap would then strand an extension. Revisit decision 6 if an optional member is ever ignored in a
way that changes behavior without being marked critical. Revisit the release paths once the bootstrap
host has shipped and the host compatibility suite has gated at least one host-only release.
