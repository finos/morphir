---
type: Decision Record
title: SemVer is the default contract versioning scheme
state: Accepted
decided: 2026-09-22
tags: [versioning, semver, compatibility, protocol, schema, mep, workspace, distribution]
status: stable
description: Every versioned contract Morphir defines uses SemVer 2.0 strings by default, with prerelease versions that match only exactly, so a contract can be refined as a draft and then frozen. Morphir IR formatVersion is not affected.
sources:
  - id: spec
    resource: https://github.com/finos/morphir/discussions/921
    title: "finos/morphir#921: capability statements across the extension lifecycle (working spec)"
  - id: single-file-thread
    resource: https://github.com/finos/morphir/discussions/915
    title: "finos/morphir#915: a single file is a synthesized project (working thread)"
---

# SemVer is the default contract versioning scheme

Every versioned contract that Morphir defines uses a SemVer 2.0 version string, unless a recorded
exception says otherwise. A contract is a protocol, a document or schema format, or a capability
statement. A new contract uses this scheme without a separate decision.

This record does not supersede any decision about the Morphir IR `formatVersion`. The IR keeps its
own versioning, including support tables
([morphir-ir 0016](https://github.com/finos/morphir/blob/main/kb/bundles/morphir/morphir-ir/decisions/0016-support-tables-are-intervals-and-a-patch-changes-nothing-observable.md))
and package release versions
([morphir-ir 0017](https://github.com/finos/morphir/blob/main/kb/bundles/morphir/morphir-ir/decisions/0017-package-release-versions-belong-to-distribution-bindings.md)).

## The rules

1. **The version is a SemVer 2.0 string**, for example `1.0.0-draft.1` or `1.0.0`.
2. **A released version is compatible within its major.** A reader that knows `1.2.0` accepts
   any `1.x.y`. A reader ignores members it does not understand, unless a `critical` list names
   them. A breaking change takes a new major.
3. **A prerelease version matches only exactly.** A reader accepts a draft such as
   `1.0.0-draft.3` only when it names that exact version. Drafts are refined in place and promise
   no compatibility with each other.
4. **Precedence follows SemVer.** `1.0.0-draft.3` is lower than `1.0.0`, so a reader that knows
   the release never takes a draft for it.
5. **A reader supports a range**: the current released major, the previous released major, and
   the exact drafts it lists.

## Why

Several contracts in flight are pre-release and change often: the capability statement, the
release descriptor and the workspace discovery protocol. Each had its own convention: an integer,
a `major.minor` string, or "stays at version 1 while pre-release". None could say "this is a draft
and may still change" in a way a reader could check. A host released against one draft could not
tell a later, incompatible draft apart from it.

SemVer prerelease tags state that directly. A draft is marked in the version itself, the exact
match rule stops a released host from misreading a changed draft, and the freeze is a visible
event: the version loses its prerelease tag. Making the scheme the default removes the question
from every future contract, so it does not need to be decided again each time.

| Option | Outcome | Why |
| --- | --- | --- |
| SemVer strings with exact-match drafts, as the default | Chosen | Drafts are explicit and checkable, and every contract follows one rule |
| Integers or `major.minor` strings, chosen per contract | Rejected | Cannot mark a draft; each contract needs its own decision |
| SemVer only for new contracts, with no default | Rejected | The question comes back with every contract |
| Apply to Morphir IR `formatVersion` too | Rejected | The IR has its own versioning decisions, which this record does not reopen |

## Recorded exceptions

- **The Morphir Extension Protocol** keeps `major.minor` protocol versions, currently `0.1`,
  until the next change to the protocol. That change adopts SemVer.
- **Morphir IR `formatVersion`** is outside this record, as stated above.

## Consequences

- The capability statement starts at `statementVersion` `1.0.0-draft.1`.
- The extension release descriptor moves to `schemaVersion` `2.0.0-draft.1`. Readers keep accepting
  the existing integer and `major.minor` values as version 1.
- The workspace discovery protocol moves from the integer `1` to `1.0.0-draft.1`. This replaces the
  earlier ruling in #915 that the protocol "stays at version 1 while pre-release": the intent is
  the same, and the draft tag now states it.
- `AGENTS.md` states the default, so contributors and agents apply it without being asked.

## Revisit when

Revisit if a contract needs to evolve two incompatible released majors within one host release
cycle, since the range covers only the current and previous majors.
