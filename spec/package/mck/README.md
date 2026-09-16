# MCK package suite, draft cases

This directory holds candidate cases for the package suite of the [Morphir Compatibility Kit](../../mck/README.md).
The [Library contract](../library-contract.md) specifies the restricted `0.1.0-draft.1`
profile described here. Stable case IDs identify expected behavior within this draft.
Record the repository commit when comparing runs; no kit-release or package compatibility
claim follows merely from a local pass.

Run `mise run package:check` for the shared-core suite, in-process and over an executable adapter.
Run `mise run package:schema-check` separately for generic schema and example structure validation.

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

Package reports record suite, contract and driver versions, testee identity and capabilities,
and a content hash of all consumed corpus, schema and fixture bytes. Record both repository
commits alongside reports when comparing development checkouts. The existing IR embedded-kit lock
does not identify this package corpus.

The shared package runner must reject unknown case targets, duplicate IDs, empty corpora,
and malformed expectations. Tooling or schema infrastructure failures must be kit errors,
not successful rejection cases. Required-case failures, kit errors, and skips prevent a
compatibility claim. Independent implementations under test use the same runner through
its interfaces or adapters; duplicating the runner is not an independence requirement.
