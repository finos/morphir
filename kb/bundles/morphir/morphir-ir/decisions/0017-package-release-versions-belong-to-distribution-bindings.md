---
type: Decision Record
title: Package release versions belong to distribution bindings
description: Package release versions come from packaging and distribution bindings without adding versions to core IR definitions or references.
state: Accepted
decided: 2026-09-16
tags: [ir, packages, distributions, versioning, mck]
status: draft
sources:
  - resource: https://github.com/finos/morphir/blob/0e79ee2ed25876780dbbae5d91147d55050019cc/kb/bundles/morphir/morphir-package-system/package-system-design.md
    title: Approved package-system design before bounded resolution implementation
  - resource: https://github.com/finos/morphir/blob/0e79ee2ed25876780dbbae5d91147d55050019cc/kb/bundles/morphir/morphir-ir/decisions/0015-dependency-directories-are-nested-with-a-version-segment.md
    title: Dependency directory delimiter decision
---

# Package release versions belong to distribution bindings

We kept package release versions in packaging metadata and distribution binding context. Core IR definitions,
dependency names, and FQNames remained release-version-free. This decision clarified the source of a future
dependency version slot; it retained [decision 0015's directory delimiter](/decisions/0015-dependency-directories-are-nested-with-a-version-segment.md).

## Summary

A release version identifies a published package, while an IR name identifies a declaration in a consuming
binding context. Requiring both to carry the version would couple reusable model definitions to publication.
The [package-system design](../../morphir-package-system/package-system-design.md) already separated those responsibilities.

| Option | Outcome | Why |
| --- | --- | --- |
| Supply release versions through packaging and distribution bindings | Chosen | Exact selection can change without rewriting model names. |
| Require release versions in core definitions or FQNames | Rejected | Publication identity would become part of reusable model content. |
| Populate versioned directories before readers support graph-aware bindings | Rejected | A directory spelling alone cannot define reference resolution. |

## Why

Packaging can select `example.com/finance/eligibility@1.3.0` for IR package name `example/eligibility`.
The reference `example/eligibility:decision#default-decision` remains unchanged. A consuming package's binding
identifies which release supplies that declaration. SemVer eligibility does not prove type compatibility.

Decision 0015 described filling the reserved slot once the model carried a package version. We did not adopt
that phrase as a prerequisite for core IR. A future distribution manifest can carry exact binding metadata
without adding release versions to every definition or reference. The historical record remains unchanged.

## Consequences

The current layout remains `deps/<escaped-package-path>/@/<escaped-module-path>/...`. This decision did not
authorize populated slots, change a codec, or add multiple-release support to a flat dependency map.
The bounded [resolution contract](../../../../../spec/package/resolution-contract.md) covers selection and exact replay;
its metadata projection is not the full installable `morphir.lock`.

Common single-binding packaging does not wait for advanced reference encoding. Graph-aware coexistence,
package-instance identity, explicit direct multi-binding, and versioned directory serialization remain
Stage 3 work. Their implementations must pass versioned MCK cases before claiming support.

## Revisit when

Stage 3 must settle the exact distribution and reference encoding, supported IR format release, and migration
rules together. A need to distinguish references inside one consumer may require explicit binding identifiers;
this decision did not choose their spelling or imply that identical FQNames can express different intentions.
