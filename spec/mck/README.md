# Morphir Compatibility Kit (MCK)

The Morphir Compatibility Kit is the collection of executable compatibility suites shared by Morphir implementations.
Each suite defines observable behavior through stable cases, expected results, and machine-readable reports.

## Suites

| Suite | Contract | Location and status |
| --- | --- | --- |
| IR | IR serialization, normalization, diagnostics, and document-tree behavior | [IR suite](../ir/mck/README.md), implemented |
| Package | Package identities, exports, manifests, locks, digests, resolution, trust, and materialization | [Draft suite](../package/mck/README.md) executes Library schema, normalization/digest, and closed-set integrity cases through the shared TypeScript core; wider Stage 0 work remains in [issue #800](https://github.com/finos/morphir/issues/800) |

Use **MCK IR suite** and **MCK package suite** when identifying a domain. "Conformance corpus" describes a collection
of cases; MCK is the shared name. Generated naming and format-version fixture filenames remain stable.

Model packages, executable extensions, and installable tools retain their own artifact domains. Sharing MCK infrastructure
does not require shared manifests, lifecycle rules, or test operations.

The first package slice provides `mise run package:check` for shared-core execution and
`mise run package:schema-check` for generic schema/example validation. The lock-core omits acquisition and trust;
it cannot authorize installation. Package execution runs in the shared MCK runner, not in a separate
compatibility runner per implementation.

## Ownership and transition

On 2026-09-18 ownership of all shared MCK tooling moved to this repository, in Rust, delivered as `morphir mck`.
[Decision 0003](../../kb/bundles/morphir/morphir-package-system/decisions/0003-mck-tooling-lives-in-the-rust-morphir-cli.md)
records it and supersedes the ownership portion of
[decision 0001](../../kb/bundles/morphir/morphir-package-system/decisions/0001-package-compatibility-uses-the-shared-mck-core.md).

**The Rust tooling is incomplete.** `morphir mck check`, `kit status`, and `kit vendor` and `kit update` exist (IR-1, IR-1V); `run`, coverage and the schema and report gates do not. Everything under "Current driver and contracts" still describes the
TypeScript driver, which stays the authoritative gate until cutover. Its MCK features are frozen.

| Document | Content | Status |
| --- | --- | --- |
| [cli-contract.md](cli-contract.md) | `morphir mck` commands, required `--adapter`, filter syntax, transport limits, reports and provenance | Approved 2026-09-18 |
| [kit-manifest.md](kit-manifest.md) | Vendored kit snapshots, `mck-kit.lock.json`, acquisition and trust | Approved 2026-09-18 |
| [migration.md](migration.md) | Consumer inventory, parity method, approved departures, cutover conditions | Approved 2026-09-18 |
| [baseline/](baseline/README.md) | Frozen old-driver reports, protocol transcript and hash vectors | Captured 2026-09-18 |

Delivery is IR first ([#851](https://github.com/finos/morphir/issues/851)), then the package suites
([#852](https://github.com/finos/morphir/issues/852)); parent tracking is [#849](https://github.com/finos/morphir/issues/849).

## Current driver and contracts

The driver lives in [finos/morphir-typescript](https://github.com/finos/morphir-typescript/tree/main/packages/mck),
under `@finos/morphir-mck`. Its current protocol and report contract version 1 describe the IR suite.
The [IR suite README](../ir/mck/README.md) specifies its case grammar and invocation.

The driver supports an in-process binding and executable adapters using a JSON-lines protocol. Its packaged form
includes an embedded kit; `--kit` selects a checkout instead. The embedded `kit.lock.json` records repository, path,
commit, and content hash. Driver releases and kit revisions must be identified separately when comparing results.

Package support uses its own experimental `0.1.0-draft.1` adapter and report contracts. IR protocol version 1
rejects unknown operations and fields, and its reports require IR-specific fields such as `irVersion` and `profile`.
The draft package contract defines suite identity, four operations, required capabilities, and package report records.
The shared core runs other implementations through adapters. Independent implementations
under test can share a runner; independently rewritten runners are not an interoperability requirement.
Reuse case loading, adapter transport, provenance, and reporting components where their semantics fit. Existing IR
commands, case IDs, and version 1 contracts remain supported through that evolution.

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
