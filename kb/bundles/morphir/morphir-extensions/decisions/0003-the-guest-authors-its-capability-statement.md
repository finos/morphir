---
type: Decision Record
title: The guest authors its capability statement
state: Accepted
decided: 2026-09-22
tags: [extensions, capabilities, mep, distribution, release]
status: stable
description: The extension itself is the only author of its capability statement, which packaging captures with morphir.extension.describe, publish accepts for process bundles, install probes on the selected artifact, and each artifact carries separately.
sources:
  - id: spec
    resource: https://github.com/finos/morphir/discussions/921
    title: "finos/morphir#921: capability statements across the extension lifecycle (working spec)"
  - id: single-file-spec
    resource: https://github.com/finos/morphir/discussions/917
    title: "finos/morphir#917: a single file is a synthesized project (spec)"
---

# The guest authors its capability statement

The extension program that the host runs, the guest, is the only author of its capability statement.
Every phase from packaging to a session carries that statement unchanged or checks it against a fresh
answer from the guest. These are decisions 1 to 5 of finos/morphir#921 (source `spec`):

| # | Decision |
| --- | --- |
| 1 | The guest is the only author of its capabilities. Packaging captures the guest's own capability statement and carries it unchanged. No capability is declared by hand in a TOML or JSON manifest. |
| 2 | `morphir extension repository publish` accepts process bundles as well as WASM bundles. |
| 3 | A new protocol method, `morphir.extension.describe`, returns the capability statement. It is allowed before `morphir.initialize` and has no side effects. |
| 4 | `morphir extension install` probes the artifact it selected with `describe` and refuses on a mismatch. `extension install --no-probe` skips the probe. |
| 5 | Each artifact carries its own statement. Artifacts of one release may differ under two guards: the release declares the difference, and install and `extension info` show it. |

[Capability statements across the extension lifecycle](/design/capability-statements.md) is the
narrative home. It gives the statement shape, the lifecycle phases and the schema-2 bundle descriptor.

## Summary

Before this decision, three places stated an extension's capabilities: the guest at
`morphir.initialize`, a hand-written release descriptor, and the host's parsers. The host compared the
first two at every session and refused when the capability kinds differed. Each new capability needed
an edit in every place. The Elm process extension could not reach an installed record at all, because
publish accepted only WASM bundles. The decision makes the guest the single source and gives every
phase a side-effect-free way to ask it.

| Option | Outcome | Why |
| --- | --- | --- |
| The guest is the only author; packaging captures its statement | Chosen | A stored statement cannot drift from the guest that wrote it |
| Publish accepts process bundles | Chosen | Without it, no tool turns an Elm release into an installed record |
| A `describe` method, allowed before `initialize`, with no side effects | Chosen | Makes "no side effects" the contract of a method, and costs less than a session |
| Install probes the selected artifact, with `--no-probe` to skip | Chosen | Finds a mismatch at install instead of at first compile |
| One statement per artifact, under two guards | Chosen | Keeps real platform differences visible and catches accidental ones |
| Keep adding boolean keys to the descriptor | Rejected | Every capability needs a key, a writer per language, a parser change and a CLI release |
| Probe only at publish | Rejected | The publisher cannot run every platform of a process release |
| Reuse `initialize` for the probe | Rejected | Heavier than needed; "no side effects" would be only a convention |
| One statement shared by every artifact | Rejected | Hides real differences between artifacts of one release |
| A merged statement in the index record | Rejected | Claims a capability that some installed artifact lacks |
| No install probe | Rejected | A mismatch shows up only at first compile |

## Why

The guest already knows its capabilities, because it reports them at `initialize`. Every other copy
was a second author. The host compared the copies at each session, so a mismatch surfaced as "capability
kinds changed" on the user's machine, after install. When packaging asks the guest and stores the
answer, the copies come from one author and agree by construction.

A separate `describe` method was needed to ask the guest outside a session. It runs before
`initialize`, takes the protocol versions the caller understands, and returns the statement. The guest
must not read a workspace, open a network connection, write files, or depend on environment values
other than those the host passes. That contract is what lets publish and install start a guest safely.
A guest that does not implement `describe` still works, through a fallback session; decision
[0004](/decisions/0004-readers-ignore-unknown-members-unless-critical.md) records that rule.

Publish had to accept process bundles because the Elm extension is a process extension. It releases six
archives and a `.release.json` with an `artifacts[]` list, and no tool turned that release into an
installed record. The only installed Elm records came from hand-written index lines in tests (source
`spec`). [Elm extension delivery](/design/elm-extension-delivery.md) describes that gap from the delivery
side.

The install probe exists because only install has the artifact that will run. A process release has
platforms the publisher cannot run, so a publish probe covers only some artifacts. Install selects one
artifact for the user's platform, verifies its digest, and asks it for its statement. A mismatch then
stops the install instead of the first compile.

For a process artifact, the probe starts a native executable with the user's rights. The launch rules
are those of a session: a cleared environment with an allow-list, an explicit working directory, a
request timeout, and kill on drop. There is no operating-system sandbox. The executable would get the
same rights at first compile, so the probe moves the first execution earlier and adds no new right.
`--no-probe` is for users who do not accept execution at install time. A WASM artifact runs
memory-isolated with no direct file or network access.

Statements are per artifact because artifacts of one release can differ for real reasons, for example
a WASM artifact and a process artifact of the same release. The two guards separate an intended
difference from a platform bug. The bundle descriptor has a `platformDifferences` value of `"none"` or
`"declared"`. When the probed statements differ and the value is `"none"`, the release job fails. When
the difference is declared, install and `extension info` show it to the user.

## Alternatives rejected

### Keep adding boolean keys to the descriptor

This was the existing practice, for example `workspaceDiscovery` in step 5 of finos/morphir#917 (source
`single-file-spec`). Each new capability needs a descriptor key, a writer in each language, a host parser
change and a CLI release. The keys also restate what the guest already reports, so they can disagree
with it.

### Probe only at publish

A publisher runs on one platform. A process release covers six, so a publish probe cannot check most of
them. The artifact that will run exists only on the user's machine, which is where install runs.

### Reuse `initialize` for the probe

A session costs more than a probe needs. Also, `initialize` has no side-effect contract, so
"the probe does nothing" would be a convention that each guest may or may not follow. A dedicated
method makes it part of the protocol.

### One statement shared by every artifact

A shared statement hides real differences, for example between a WASM and a process artifact of one
release. It also hides accidental ones, which the per-artifact comparison at release time catches.

### A merged statement in the index record

A merge, such as a union of all artifacts' capabilities, would claim a capability that some installed
artifact lacks. The index record keeps every statement instead.

### No install probe

Without it, a mismatch between the record and the artifact shows up only at first compile. That is the
failure this decision set out to move earlier.

## Consequences

- Release tooling for each extension runs `describe` once per platform and writes the answers into a
  schema-2 bundle descriptor. `.github/extensions.toml` capability flags in finos/morphir-rust and
  capability entries in `extension.json` in finos/morphir-elm stop being authored by hand.
- MEP gains `morphir.extension.describe`. The MEP draft (`docs/design/draft/extensions/protocol.md`) does
  not describe it yet.
- `repository publish` accepts process bundles, verifies every digest and checksum, and probes each
  artifact that runs on the publishing host.
- `extension install` starts the selected artifact once at install time, unless the user passes
  `--no-probe`.
- A new capability needs a change in the guest only, provided readers follow the compatibility rules of
  decision [0004](/decisions/0004-readers-ignore-unknown-members-unless-critical.md).
- A probe proves agreement between a record and the guest, not that the guest does what it states.
  Evidence for that stays with the Morphir Compatibility Kit, per
  [Extensions declare IR capability sets](/decisions/0002-extension-capability-sets.md).

## Revisit when

Revisit the install probe if an operating-system sandbox for process probes becomes available on the
supported platforms, since that changes what `--no-probe` protects against. Revisit the per-artifact
rule if declared platform differences turn out to be common, since frequent differences would suggest
that one release should be several. Revisit the `describe` contract if a guest cannot give a correct
statement without reading its environment.
