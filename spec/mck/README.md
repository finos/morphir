# Morphir Compatibility Kit (MCK)

The Morphir Compatibility Kit is the collection of executable compatibility suites shared by Morphir implementations.
Each suite defines observable behavior through stable cases, expected results, and machine-readable reports.

## Suites

| Suite | Contract | Location and status |
| --- | --- | --- |
| IR | IR serialization, normalization, diagnostics, and document-tree behavior | [IR suite](../ir/mck/README.md), implemented |
| Package | Package identities, exports, manifests, locks, digests, resolution, trust, and materialization | [Draft suite](../package/mck/README.md) executes 80 integrity and 78 resolution cases through `morphir mck package run`; both independent adapters run under the native runner. Wider Stage 0 work remains in [issue #800](https://github.com/finos/morphir/issues/800) |
| MEP | Messages between a Morphir host and an extension, from the [MEP contract](../mep/README.md) | Planned in `spec/mep/mck/`, [issue #965](https://github.com/finos/morphir/issues/965) |

Use **MCK IR suite** and **MCK package suite** when identifying a domain. "Conformance corpus" describes a collection
of cases; MCK is the shared name. Generated naming and format-version fixture filenames remain stable.

Model packages, executable extensions, and installable tools retain their own artifact domains. Sharing MCK infrastructure
does not require shared manifests, lifecycle rules, or test operations.

The package slice provides `mise run package:check` for native execution against TypeScript and
`mise run package:schema-check` for generic schema/example validation. The lock-core omits acquisition and trust;
it cannot authorize installation. Package execution runs in the shared MCK runner, not in a separate
compatibility runner per implementation.

## Ownership and transition

On 2026-09-18 ownership of all shared MCK tooling moved to this repository, in Rust, delivered as `morphir mck`.
[Decision 0003](../../kb/bundles/morphir/morphir-package-system/decisions/0003-mck-tooling-lives-in-the-rust-morphir-cli.md)
records it and supersedes the ownership portion of
[decision 0001](../../kb/bundles/morphir/morphir-package-system/decisions/0001-package-compatibility-uses-the-shared-mck-core.md).

**Parent IR gates use the Rust CLI.** Kit checking and vendoring, adapter runs, coverage,
offline schema validation, independent report checking and optional HTML rendering are implemented.
The report contract remains `2.0.0-draft.1`. Native beta.3 is qualified on six targets for IR and both existing package contracts. Parent package gates and the TypeScript installed-adapter gate use the native runner. TypeScript runner paths and temporary live parity tooling are retired; independent adapters, implementation helpers and draft.3 support remain. Rust's IR-only consumer retains its qualified beta.2 pin.

| Document | Content | Status |
| --- | --- | --- |
| [cli-contract.md](cli-contract.md) | `morphir mck` commands, required `--adapter`, filter syntax, transport limits, reports and provenance | Approved 2026-09-18 |
| [kit-manifest.md](kit-manifest.md) | Vendored kit snapshots, `mck-kit.lock.json`, acquisition and trust | Approved 2026-09-18 |
| [migration.md](migration.md) | Consumer inventory, parity method, approved departures, cutover conditions | Approved 2026-09-18 |
| [CLI and library migration guide](../../docs/developers/mck-native-migration.md) | Consumer commands, release and kit pins, CI failure handling and draft report migration | IR-4 adoption guidance |
| [baseline/](baseline/README.md) | Frozen old-driver reports, protocol transcript and hash vectors | Captured 2026-09-18 |

Delivery is IR first ([#851](https://github.com/finos/morphir/issues/851)), then the package suites
([#852](https://github.com/finos/morphir/issues/852)); parent tracking is [#849](https://github.com/finos/morphir/issues/849).

## Retained TypeScript adapters and implementation support

[`@finos/morphir-mck`](https://github.com/finos/morphir-typescript/tree/main/packages/mck)
retains the TypeScript IR/package adapter and independent implementation helpers.
The `mck` runner bin and package runner APIs are removed from future artifacts;
use `morphir mck` with an explicit adapter. Standalone executables contain the
adapter only. Existing published versions and assets remain available.

Package support keeps its experimental `0.1.0-draft.1` and `0.1.0-draft.2`
contracts. Draft.3 groundwork and restore remain tracked separately in [#852](https://github.com/finos/morphir/issues/852).
The IR adapter protocol remains version 1 and the native report is independently
versioned. An IR pass does not establish package compatibility.

## Compatibility claims

A compatibility claim identifies the suite, kit revision, driver version, adapter contract, and required capabilities.
Every required case must pass. Failures, kit errors, and skipped required cases prevent the claim.

The IR driver may exit successfully while unsupported capabilities are skipped. `--strict` fails on all skips;
a claim covering a narrower capability set needs an explicit gate for its required cases. An IR-only pass does not
establish package compatibility. Running one implementation in-process and through its adapter tests transport agreement;
the package design's two-implementation criterion requires independent implementations. The draft package command
always fails on any skip, failure, kit error, or empty corpus.

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

Package integration extends this baseline through [TypeScript PR #16](https://github.com/finos/morphir-typescript/pull/16),
rebased onto commit `872ece8`, including the 0.1.0 publication and the Effect-based CLI.
Dependent draft PRs may pin its published feature commit for integration checks. Before merging the parent,
land the TypeScript PR and pin its merged commit. Never publish a parent commit requiring uncommitted submodule files.
The [package-system design](../../kb/bundles/morphir/morphir-package-system/package-system-design.md)
records how these IR changes affect Stage 0 and the later delivery stages.
