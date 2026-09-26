# MCK IR migration baseline, 2026-09-18

Frozen evidence of what the TypeScript MCK driver does, captured before any Rust MCK code exists.
The Rust runner is measured against it under the rules in [migration.md](../migration.md).
These files are evidence. Do not regenerate them to make a parity check pass; a new capture is a
new dated baseline beside this one.

The Markdown case grammar and the dual-engine parity task retired after the Gherkin cutover
in #946. The inventories, reports and transcripts here describe the historical kit and remain
frozen evidence; current IR runs use `.feature` cases and driver contract 2.

## Kit snapshot before Ion case migration

`kit-2026-09-26/` is a managed, self-contained copy of the Gherkin kit at parent commit
`a8293bdf22607ff2dfe2dba51543d4040322cc77`. It was created with
`morphir mck kit vendor --source . --dest spec/mck/baseline/kit-2026-09-26`.
Its snapshot digest is
`sha256-c1fbce52a8d002c1e70de4ff8214dbb6a7a1ecdb8a8d6e79a50c7b0643fbfe61`.
The frozen reports and transcripts continue to replay against this kit as the live
`spec/ir/mck/` cases move to Ion. This snapshot does not change any historical
report or transcript byte. New captures go in a separate dated baseline.
The first Ion exchange is in [baseline-ion-2026-09-26](../baseline-ion-2026-09-26/README.md).

A kit addition, such as the [IR 3.1.0 cases](#ir-310-update), is the one exception. It updates these
files in place, and only by addition:

- Every earlier record and exchange stays unchanged and keeps its order relative to the others. The
  new ones go where the kit runs them, which can be between earlier ones.
- The only changes an earlier entry may take are the ones the addition forces: a transcript
  request's `id`, which counts requests in run order, and the binding's `formatVersions` in its
  `capabilities` response and its report header, when the addition changes its support table.
  `durationMs` is not evidence; parity ignores it.
- New exchanges are recorded with the native engine through `tools/record-mck-transcript.ts`. The old
  driver is not used again.

[finos/morphir#987](https://github.com/finos/morphir/issues/987) tracks tooling that records an
addition and checks these rules.

## Pins

| Item | Revision |
| --- | --- |
| finos/morphir (kit and tools) | `a2803f2cbfbb9baffe8a939e9462b18fd5bcdda0` |
| finos/morphir-typescript (old driver 0.3.0 and `mck-adapter-typescript`) | `a5e3be0922ce2dad1920956a8c7bfe6616d515d5` |
| finos/morphir-rust (`mck-adapter-rust`) | `bbab67aa40388f1b92b0a20948faf34c68ca1189` |
| Kit embedded in the old driver | finos/morphir `2bab57ea23fe85c6f9cc434b32e61f29ca14190c` |
| Corpus hash, checkout and embedded kit alike | `sha256-075bb621c9901fcca21830051065b3d5f303dfb827b1624c52c82d796bf4c609` |

The embedded kit's commit differs from the checkout, but `spec/ir/mck` and its external fixture did
not change between them, so both hash the same.

The change that added this baseline also added a transition note to `spec/ir/mck/README.md`, which
is part of the corpus. From that commit the corpus hash is
`sha256-97e68b0ee68b4236750a88d9695d41896cdefa0291097e529b972ddebdacde8c`. No case changed, so the
reports and transcript are unaffected.

## Results

| Command (old driver, `--kit spec/ir/mck`) | Result |
| --- | --- |
| `check spec/ir/mck` | 120 cases in 8 files, 0 errors, exit 0 |
| `run --adapter bun --adapter-arg .../adapter.ts` | 722 pass, 0 fail, 0 kit-error, 8 skipped, exit 0 |
| `run` in-process | Identical report apart from `startedAt` and `durationMs` |
| `run --adapter mck-adapter-rust` | 730 pass, 0 fail, 0 kit-error, 0 skipped |
| `coverage` | every vocabulary entry has a case, exit 0 |
| `kit status` | matches `kit.lock.json`, exit 0 |

The 8 TypeScript skips are `versions-0001`, `-0006`, `-0007` and `-0008`, fence 0, on both paths,
each `version 3 not in capabilities`. The Rust binding declares `[3.0.0,3.2.0),[4.0.0,4.1.0)` and
runs them. `allowed-failing.json` for the Rust adapter is empty.

## IR 3.1.0 update

The IR 3.1.0 cases (`document-tree-0010` to `-0017`, `versions-0009`, `versions-0010` and
`distributions-0011`, all at version 3) change three baseline files. The table above records the
old driver's run and stays as it was.

- `reports/morphir-typescript.json`: 722 pass, 0 fail, 0 kit-error, 80 skipped. The 72 new skips
  are the new version 3 fences, each `version 3 not in capabilities`. The header and the 730
  earlier records are unchanged and in the same order, apart from each record's `durationMs`,
  which the IR 3.1.0 run wrote again. The TypeScript transcript does not change, because a skipped
  fence sends no request.
- `transcripts/morphir-rust.ndjson` and `reports/morphir-rust.json`: 802 pass, 0 fail, 0
  kit-error, 0 skipped. The transcript was recorded again with the native engine through the
  same proxy: `morphir mck run --kit spec/ir/mck --adapter bun --adapter-arg run --adapter-arg
  tools/record-mck-transcript.ts --adapter-arg <transcript> --adapter-arg <mck-adapter-rust>`,
  at the morphir-rust pin `b488805`. It holds 772 requests: 1 `capabilities`, 722 `decode`, 26
  `readTree`, 22 `writeTree`, 1 `exit`. Its largest message is 4 607 bytes, and it contains no
  machine-specific path. The old driver's 714 requests and 713 responses are all in it, unchanged
  and in the same order, apart from two changes the addition forces: each request's `id` counts
  the 58 new requests between them, and the `capabilities` response says
  `[3.0.0,3.2.0),[4.0.0,4.1.0)`. The report keeps its version 1 header, with the same change to
  `formatVersions`. Its 730 earlier records are unchanged, `durationMs` included, and in the same
  order. The 72 new records, the first at index 204, came from replaying the new transcript
  through the historical `runner_parity` test; current replay coverage is in
  `crates/morphir/tests/mck_run.rs`.

## Files

| File | Content | How it was captured |
| --- | --- | --- |
| `reports/morphir-typescript.json` | Version 1 report, TypeScript adapter | Header and 730 records: a local run of the old driver on Windows 11 with Bun 1.4.2 (their `durationMs` values are from the IR 3.1.0 run). 72 records: the [IR 3.1.0 update](#ir-310-update) |
| `reports/morphir-rust.json` | Version 1 report, Rust adapter | Header and 730 records: artifact `mck-report-morphir-rust` of finos/morphir CI run [35407504580](https://github.com/finos/morphir/actions/runs/35407504580) on `main` at the parent pin, Linux (the header's `formatVersions` is from the IR 3.1.0 update). 72 records: the [IR 3.1.0 update](#ir-310-update) |
| `transcripts/morphir-typescript.ndjson` | Every protocol message of the TypeScript adapter run, as `{"dir":"request"\|"response","message":...}` lines | A recording proxy between the old driver and the adapter. 706 requests: 1 `capabilities`, 678 `decode`, 14 `readTree`, 12 `writeTree`, 1 `exit`. Largest message 4 635 bytes. It contains no machine-specific path. |
| `transcripts/morphir-rust.ndjson` | The same, for the Rust adapter run | 714 of its 772 requests and their responses: the old driver's session, recorded through `tools/record-mck-transcript.ts` by `mise run mck:parity-rust` (1 `capabilities`, 686 `decode`, 14 `readTree`, 12 `writeTree`, 1 `exit`; largest message 4 607 bytes). The other 58 requests (36 `decode`, 12 `readTree`, 10 `writeTree`), the request `id`s and the `capabilities` response's `formatVersions`: the native engine at the [IR 3.1.0 update](#ir-310-update). It contains no machine-specific path. |
| `corpus-inventory.json` | The 15 paths of the legacy corpus set and their hash | The old driver's `collectSnapshot` and `contentHash` |
| `kit-cases.json` | The old parser's reading of every case file: ids, heading keys, prose, and each fence's info, body and line, with the file's SHA-256 | The old driver's `loadKit`, added with IR-1. `crates/morphir-mck/tests/typescript_parity.rs` compares the Rust parser with it for every file whose digest still matches |
| `hash-vectors.json` | Literal vectors for `mck-file-map-sha256/1` | The old driver's `contentHash`; the `single` vector was recomputed independently with .NET SHA-256 |

The proxied run's report equals `reports/morphir-typescript.json` under the parity exclusions, so
the transcript and the report describe the same run.

The Rust adapter's transcript was added in IR-2, recorded on Windows 11 against the adapter at the
parent's current submodule pin. That pin does not change `crates/morphir-mck-adapter`. Two things
make it platform-independent evidence rather than one machine's:

- `mise run mck:parity-rust` recorded the same session on Linux in CI run
  [35470698507](https://github.com/finos/morphir/actions/runs/35470698507), and that recording was
  byte-identical to this file as it stood before the IR 3.1.0 update, all 401 760 bytes. The update
  changed the file (see [IR 3.1.0 update](#ir-310-update)), so the byte comparison holds for that
  earlier file only.
- Replaying it reproduced `reports/morphir-rust.json`, captured on Linux at the earlier pin, record
  for record. Both platforms and both revisions agreed. The replay of the updated transcript
  reproduces the 730 earlier records the same way.

## Package baseline, 2026-09-21

`package-cases.json` is separate frozen evidence for PKG-1. It was captured from
TypeScript `4ae09cbd574c98aefacfd4696132001b770bb1bf` against the package corpus
in parent `26ef146dba42bf355eb922aa24396697328b4efa`. `loadPackageKit` and
`loadResolutionKit` provide the ordered case inventories; each contract's
`projectResult` provides the expected comparison value. No adapter is used to
compute these expectations.

Each case records its ID and separate SHA-256 digests of its request and projected
expectation. The digest input is compact UTF-8 JSON with object members in UTF-16
key order, unchanged array order and unchanged strings. This includes the complete
raw operation input string, so changing fixture mutation or serialization behavior
changes the request digest even when the corpus files themselves are unchanged.
The Rust regression compares all 158 cases and the original corpus hashes.
Do not regenerate this file to make a port pass.
