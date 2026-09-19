---
type: Decision Record
title: Package compatibility uses the shared TypeScript MCK core
description: Package compatibility cases use the shared TypeScript MCK tooling and implementation adapters rather than separate compatibility runners.
state: Superseded
superseded_by: "0003"
decided: 2026-09-16
tags: [mck, packages, tooling, typescript, adapters]
status: stable
---

# Package compatibility uses the shared TypeScript MCK core

We retained the shared MCK tooling in finos/morphir-typescript as the home for package
compatibility execution. We kept specifications, schemas, cases, and fixed expected results
in finos/morphir. Other implementations reuse that tooling through an in-process interface
or an adapter. We rejected a parallel compatibility runner in the parent repository,
whether written in Python, TypeScript, or JavaScript.

This decision clarified how the existing MCK architecture applies to the
[package system](/package-system-design.md). It did not establish a new competing kit.

## Summary

The first package prototype introduced standalone TypeScript and Python digest checks.
They provided useful experimental evidence, but duplicated responsibilities already assigned
to MCK. Independent implementations under test do not require independent test runners.

| Option | Outcome | Why |
| --- | --- | --- |
| Extend the shared TypeScript MCK core and use implementation adapters | Chosen | Keeps case interpretation, comparison, reporting, and capability rules consistent |
| Maintain a separate Python compatibility checker in finos/morphir | Rejected | Adds a parallel runner and an unnecessary tooling-language dependency |
| Translate that checker to a standalone TypeScript or `.mjs` runner | Rejected | Changes the language without correcting ownership or duplication |

## Why

The [IR suite contract](../../../../../spec/ir/mck/README.md) already places the shared driver
in finos/morphir-typescript. The [stabilization design](../../morphir-ir/ir-v4-stabilization.md)
records its use for the reference binding and other bindings through adapters.
The package design already requires reuse of case loading, transport, provenance, and
reporting where their meanings fit. The standalone prototype did not follow that division.

The approved responsibilities are:

| Owner | Responsibility |
| --- | --- |
| finos/morphir | Specifications, schemas, versioned compatibility cases, fixed expected results |
| finos/morphir-typescript MCK core | Case loading, scheduling, result comparison, capability gates, provenance, reports, adapter infrastructure |
| Reference package functionality in finos/morphir-typescript | Package operations exercised by MCK, kept separate from the driver's expected results |
| Other implementations | Their package behavior and the adapter needed to expose it to MCK |

The driver compares an implementation's output with committed expectations. It must not
compute those expectations by calling that implementation during the same test.
Different transports around one implementation remain one implementation. Reusing a
reference algorithm is allowed, but does not establish independent implementation of that
algorithm for an interoperability claim. Multiple implementations can use the same driver.

## Consequences

New repository tooling prefers TypeScript. JavaScript scripts use `.mjs`. Introducing Python
or another tooling language requires an explicit, justified exception agreed with maintainers.
This preference does not prohibit Morphir language implementations or their adapters from
using their own languages, nor does it require unrelated existing Python scripts to be migrated.

Package cases need package operations and suite-aware reporting. The current IR protocol
and report version 1 remain supported and unchanged. Package support must use explicitly
versioned contracts; it must not masquerade as IR nodes or reuse IR fields with unrelated meanings.
Model packages, executable extensions, and installable tools keep distinct artifact contracts.

The first slice retains the draft schemas and candidate cases. The standalone checker and
its companion test tooling are retired from deliverable paths. Generic schema validation
can still check the artifacts, but is not a package compatibility run. Shared package runtime
support must land in finos/morphir-typescript before the parent pins and invokes it.

## Unresolved

The package operation interface, adapter protocol version, report schema, and reference-library
placement remain Stage 0 work. This decision fixes ownership and reuse, not those wire details.
The two-independent-implementations exit criterion remains open; prototype runs do not meet it.

## Revisit when

Revisit the shared-core ownership only if a concrete runtime or distribution constraint cannot
be met through its library, executable, or adapter interfaces. Convenience of a second language
or a locally duplicated runner is not sufficient evidence.
