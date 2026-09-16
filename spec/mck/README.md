# Morphir Compatibility Kit (MCK)

The Morphir Compatibility Kit is the collection of executable compatibility suites shared by Morphir implementations.
Each suite defines observable behavior through stable cases, expected results, and machine-readable reports.

## Suites

| Suite | Contract | Location and status |
| --- | --- | --- |
| IR | IR serialization, normalization, diagnostics, and document-tree behavior | [IR suite](../ir/mck/README.md), implemented |
| Package | Package identities, exports, manifests, locks, digests, resolution, trust, and materialization | Planned at `spec/package/mck/`; initial cases and driver support are Stage 0 work in [issue #800](https://github.com/finos/morphir/issues/800) |

Use **MCK IR suite** and **MCK package suite** when identifying a domain. "Conformance corpus" describes a collection
of cases; MCK is the shared name. Generated naming and format-version fixture filenames remain stable.

Model packages, executable extensions, and installable tools retain their own artifact domains. Sharing MCK infrastructure
does not require shared manifests, lifecycle rules, or test operations.

## Current driver and contracts

The driver lives in [finos/morphir-typescript](https://github.com/finos/morphir-typescript/tree/main/packages/mck),
under `@finos/morphir-mck`. Its current protocol and report contract version 1 describe the IR suite.
The [IR suite README](../ir/mck/README.md) specifies its case grammar and invocation.

The driver supports an in-process binding and executable adapters using a JSON-lines protocol. Its packaged form
includes an embedded kit; `--kit` selects a checkout instead. The embedded `kit.lock.json` records repository, path,
commit, and content hash. Driver releases and kit revisions must be identified separately when comparing results.

Package support must evolve the existing infrastructure through explicit versioned contracts. Protocol version 1
rejects unknown operations and fields, and its reports require IR-specific fields such as `irVersion` and `profile`.
Stage 0 must define suite identity, package operations, required capabilities, and report records appropriate to packages.
Reuse case loading, adapter transport, provenance, and reporting components where their semantics fit. Existing IR
commands, case IDs, and version 1 contracts remain supported through that evolution.

## Compatibility claims

A compatibility claim identifies the suite, kit revision, driver version, adapter contract, and required capabilities.
Every required case must pass. Failures, kit errors, and skipped required cases prevent the claim.

The current driver may exit successfully while unsupported capabilities are skipped. `--strict` fails on all skips;
a claim covering a narrower capability set needs an explicit gate for its required cases. An IR-only pass does not
establish package compatibility. Running one implementation in-process and through its adapter tests transport agreement;
the package design's two-implementation criterion requires independent implementations.

## Integration baseline, 2026-09-16

- Morphir [commit 2cd0dcd0](https://github.com/finos/morphir/commit/2cd0dcd0e0236a38e577eff90fad67339aa42449)
  includes the driver CI work from [PR #809](https://github.com/finos/morphir/pull/809), the merged YAML/tree integration
  in [PR #810](https://github.com/finos/morphir/pull/810), the naming clarification in [PR #812](https://github.com/finos/morphir/pull/812),
  and tracked-fixture validation plus refreshed submodule pins in [PR #813](https://github.com/finos/morphir/pull/813).
  It pins morphir-typescript to `46197e289b437038427f964cca6f1f54c03044a1`.
- TypeScript [commit 46197e2](https://github.com/finos/morphir-typescript/commit/46197e289b437038427f964cca6f1f54c03044a1)
  includes YAML and tree comparisons, reader-only `mode=read` cases, the decision 0015 dependency layout,
  and tests consuming the generated naming corpus's `qualifiedModuleNameCases`.
- Decision 0015 requires `deps/<escaped-package-path>/@<version>/<escaped-module-path>/...`. The current model uses
  bare `@` and rejects populated version slots. `ModuleName` is package-relative; `QualifiedModuleName` uses `package:module`.
  These delimiters preserve boundaries between variable-length package and module paths. They do not implement package release resolution.
- TypeScript's embedded kit pins Morphir commit `94d5cc864683a6a5f15dc90d92b70fa605f4da47`.
  Record this provenance separately from the checkout revision. Compare case content and required capabilities before
  treating runs against an embedded kit and a checkout as equivalent.

Before package implementation begins, pin a mutually compatible driver and kit revision. The [package-system design](../../kb/bundles/morphir/morphir-package-system/package-system-design.md)
records how these IR changes affect Stage 0 and the later delivery stages.
