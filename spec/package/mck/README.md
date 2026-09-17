# MCK package suite, draft cases

This directory holds candidate cases for the package suite of the [Morphir Compatibility Kit](../../mck/README.md).
The [Library contract](../library-contract.md) specifies the restricted `0.1.0-draft.1`
profile described here. Stable case IDs identify expected behavior within this draft.
Record the repository commit when comparing runs; no kit-release or package compatibility
claim follows merely from a local pass.

Run `mise run package:check` for the shared-core suite, in-process and over an executable adapter.
Run `mise run package:check:rust` for the same suite against the independent Rust implementation.
Run `mise run package:schema-check` separately for generic schema and example structure validation.

`resolution-cases.json` is the experimental `0.1.0-draft.2` resolution corpus index.
Its indexed fixtures cover all 13 families listed in the [resolution contract](../resolution-contract.md).
Cases use globally unique stable IDs, raw-string operation input, and fixed structured expected
results. Every digest in these fixtures is synthetic metadata, not a verified payload hash.
The schema task checks the index and case/result structure. Executable resolution
uses the shared TypeScript MCK core and the independent Rust implementation through an adapter.
The new `package:resolution-check` and `package:resolution-check:rust` tasks select draft.2
explicitly. Their CI integration requires the pending upstream implementation pins;
the currently recorded submodule commits still provide draft.1 only.
The existing draft.1 package suite remains available unchanged.

`schema-cases.json` declares each case's schema, base fixture, expected verdict, and
optional replacement or removal using a property-path array. Acceptance here means
structural schema acceptance only. Cross-document semantic checks must be separate operations
in the shared package suite. In particular, a valid schema does not
prove a public specification matches its selected implementation.

`digest-vectors.json` contains raw JSON inputs and fixed canonical text and digest
expectations, plus rejected documents and exact-byte cases expressed as hexadecimal.
It includes the worked manifests. These expected values are committed data, not computed
at test runtime by the implementation under test. The shared runner must compare implementation
results with these fixed expectations, not derive expectations from the same implementation.

`library-cases.json` checks the closed two-Library example against fixed accept/reject verdicts.
Mutations address `lock`, `eligibility`, or `consumer` through property-path arrays.
`payloadSuffix` appends hex bytes to a named fixture; `lockText` supplies raw lock JSON for syntax cases.
The operation verifies exact declared bytes, aggregate hashes, roots and binding targets, release
identity and stable-version intervals, IR package/dependency names, and public export targets.
It does not check public-specification compatibility, resolve versions, establish trust, or install files.

## Shared core integration

The [accepted ownership decision](../../../kb/bundles/morphir/morphir-package-system/decisions/0001-package-compatibility-uses-the-shared-mck-core.md)
places case loading, execution, comparison, capabilities, provenance, reporting, and adapter
infrastructure in finos/morphir-typescript. This directory supplies cases, not another runner.
Reference package functionality is a test target, separate from expected results.

The core exposes `PackageTestee`, `runPackageKit`, and `processPackageTestee`. Its `mck package run`
command requires `--kit`; no package corpus is embedded yet. `mck-adapter-typescript --suite package`
selects the experimental `0.1.0-draft.1` package protocol. The package protocol and report schemas
ship with `@finos/morphir-mck`. IR protocol/report version 1 and default IR commands stay unchanged.

Draft.2 adds `ResolutionTestee`, `runResolutionKit`, and `processResolutionTestee` through
the same execution, comparison, and reporting infrastructure. Select it with
`mck package run --contract 0.1.0-draft.2 --kit spec/package/mck` and
`mck-adapter-typescript --suite package --contract 0.1.0-draft.2`, or the corresponding
Rust adapter flags. Its `package-resolution-protocol.schema.json` and
`package-resolution-report.schema.json` ship with the MCK package. Omitting `--contract`
from a package invocation retains draft.1.

The Rust adapter exposes the same package contract through `mck-adapter-rust --suite package`.
Package behavior lives in the separate `morphir-package` library, not the adapter or the extension
distribution library. The parent wrapper selects the suite, optional package contract, and platform-specific
binary name. It forwards the same explicit contract to driver and adapter. The shared driver still
loads cases, compares fixed expectations and reports results.

CI writes `package-typescript.json`, `package-typescript-adapter.json`, and `package-rust.json`
under `.dev/out/mck/`. The two TypeScript transports count as one implementation; Rust supplies
the second implementation. Passing this restricted corpus does not complete all Stage 0 work.

Package reports record suite, contract and driver versions, testee identity and capabilities,
and a content hash of all consumed corpus, schema and fixture bytes. Record both repository
commits alongside reports when comparing development checkouts. The existing IR embedded-kit lock
does not identify this package corpus.

The shared package runner must reject unknown case targets, duplicate IDs, empty corpora,
and malformed expectations. Tooling or schema infrastructure failures must be kit errors,
not successful rejection cases. Required-case failures, kit errors, and skips prevent a
compatibility claim. Independent implementations under test use the same runner through
its interfaces or adapters; duplicating the runner is not an independence requirement.

## Local resolution evidence, pending landing

The 2026-09-16 development run passed all 78 draft.2 cases on each transport, with zero
failures, kit errors, or skips. The shared driver version was `0.1.0`.

| Report under `.dev/out/mck/` | Testee | Passing cases |
| --- | --- | --- |
| `package-resolution-typescript.json` | morphir-typescript `0.1.0`, in-process | 78 |
| `package-resolution-typescript-adapter.json` | morphir-typescript `0.1.0`, executable adapter | 78 |
| `package-resolution-rust.json` | morphir-rust `0.2.0`, executable adapter | 78 |

All three reports identify corpus hash
`sha256-8dfed22a389bd08e945b35213586b0709f2cf11f5426199bcec746007443b08b`.
The fixed cases cover validation phases, replay, backtracking, scoped updates, graph ordering,
and diagnostic witness ranking. They do not verify acquisition, payloads, trust, or API compatibility.

These runs used uncommitted implementation changes in isolated development checkouts,
not the recorded parent submodules. TypeScript's base was
`f308c9be27fa58af72c112fe4e16028568c3e6f4`; Rust's base was
`392c1a7078acfb459f1d335d953cc70e027971ff`. These base commits do not identify the tested
source changes. Parent base `0e79ee2ed25876780dbbae5d91147d55050019cc` still records the
TypeScript base above and Rust `05f59d7dcf36a74fefa284ca27abbfc49e56a3e3`.
Merged implementation commits, final pins, and fresh CI reports are required before a
published compatibility claim. Local reports are ignored build outputs, not committed evidence artifacts.

The separate draft.1 corpus also passed all 80 cases on each transport with no failures,
kit errors, or skips. Its hash remains
`sha256-72b6593c99af919076e59208b833771394d659838e28ee4c23554ee7f5590e23`.
Neither result completes Stage 0 or produces an installable `morphir.lock`.
