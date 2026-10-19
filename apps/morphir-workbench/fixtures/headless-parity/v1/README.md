# Independent headless parity fixtures, version 1.0.0

Inputs and expected results were frozen before actual adapter qualification.
`provenance.json` records the published parent revisions, source-file digests,
selected case IDs, subset digests and original-byte evidence. Historical subsets
retain raw JSON tokens, including the deliberate `1e999` opaque operand.

| Exact MCK draft | Cases | Operation/provider scope |
| --- | ---: | --- |
| 12 | 9 | Selected local Scheme function checking policies and exact outcomes |
| 14 | 8 | Recorded execution cursor/lifecycle and cancellation transitions |
| 17 | 9 | Controlled native client replies, unknown submission and retained bytes |
| 26 | 8 | Invocation codecs and exact values, including binary Ion |
| 27 | 12 | Source-mapped Scheme worksheets and report validation |
| 28 | 9 | Controlled artifact server bytes, ownership and release |
| 28 client | 8 | Verified artifact consumption, stale ownership and cancellation |
| 29 | 32 | Local model inspection and byte-exact originals in four representations |

The new draft.29 contract and schemas belong to the maintained parent Rust MCK,
under `spec/workbench/draft.29` and `spec/workbench/mck/draft.29` in finos/morphir.
This repository's copy is a pinned consumer fixture. Its normalized IR is an
independent expectation, never calculated from a CLI or Workbench response.
`originals/` includes JSON, YAML/YML with BOM/CRLF/comments/quoting, complete
published Ion text/binary, exact scalar models and an 11-byte binary artifact.

`yaml/cases.json` has 23 independent profile/document cases. Physical profile
scalars and resource recipes are explicitly separate from typed model assembly.
`yaml/tree-cases.json` has 16 contract-derived tree cases, frozen before assembly
output was observed. Refusals name an exact diagnostic only where the published
contract specifies one. `provenance.json` also fixes ingress selection expectations.

Run checker infrastructure controls with a parent executable supporting draft.29:

```sh
MORPHIR_MCK_BIN=/absolute/path/to/morphir \
  moon run scripts/headless-parity-controls.mbtx
```

This submits 95 fixed positive controls and nine report attacks per kit to the
existing parent checker. It neither executes nor qualifies production adapters.
The saved positive reports identify their binding as `checker-infrastructure-only`.
The parent owns all comparisons, closed schemas and resource limits. The launcher
checks fixture and runner digests before and after; reports stay under `.dev/`.

Run actual built CLI and Workbench policy qualification separately:

```sh
MORPHIR_MCK_BIN=/absolute/path/to/morphir \
  node apps/morphir/scripts/test-headless-mck.ts
```

It builds JS/native producers and the production duplicate-aware framing codec,
runs the explicit nine-case draft.12 subset through the shared runner, then
independently rechecks each saved report. The test adapter never reads this
fixture directory or receives expected observations/case IDs. It captures actual
CLI planning boundaries, outcomes and stable failure codes. Reports and a full
source/artifact/runner/corpus digest inventory live in `.dev/headless-parity-actual`.
A source change during build/qualification invalidates the receipt.

This actual adapter advertises only the selected local Scheme execute operation
with JSON argument sources. Completion validation and the full historical
draft.12 corpus require their existing adapters. Actual model draft.29 command
qualification, connected model service negotiation, publication and final
installed-platform acceptance remain with their Task 7 and service owners.
