# MCK IR migration baseline, 2026-09-18

Frozen evidence of what the TypeScript MCK driver does, captured before any Rust MCK code exists.
The Rust runner is measured against it under the rules in [migration.md](../migration.md).
These files are evidence. Do not regenerate them to make a parity check pass; a new capture is a
new dated baseline beside this one.

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

## Files

| File | Content | How it was captured |
| --- | --- | --- |
| `reports/morphir-typescript.json` | Version 1 report, TypeScript adapter | Local run on Windows 11 with Bun 1.4.2 |
| `reports/morphir-rust.json` | Version 1 report, Rust adapter | Artifact `mck-report-morphir-rust` of finos/morphir CI run [35407504580](https://github.com/finos/morphir/actions/runs/35407504580) on `main` at the parent pin, Linux |
| `transcripts/morphir-typescript.ndjson` | Every protocol message of the TypeScript adapter run, as `{"dir":"request"\|"response","message":...}` lines | A recording proxy between the old driver and the adapter. 706 requests: 1 `capabilities`, 678 `decode`, 14 `readTree`, 12 `writeTree`, 1 `exit`. Largest message 4 635 bytes. It contains no machine-specific path. |
| `transcripts/morphir-rust.ndjson` | The same, for the Rust adapter run | `mise run mck:parity-rust`, which records the old driver's session through `tools/record-mck-transcript.ts`. 714 requests: 1 `capabilities`, 686 `decode`, 14 `readTree`, 12 `writeTree`, 1 `exit`. Largest message 4 607 bytes. It contains no machine-specific path. |
| `corpus-inventory.json` | The 15 paths of the legacy corpus set and their hash | The old driver's `collectSnapshot` and `contentHash` |
| `kit-cases.json` | The old parser's reading of every case file: ids, heading keys, prose, and each fence's info, body and line, with the file's SHA-256 | The old driver's `loadKit`, added with IR-1. `crates/morphir-mck/tests/typescript_parity.rs` compares the Rust parser with it for every file whose digest still matches |
| `hash-vectors.json` | Literal vectors for `mck-file-map-sha256/1` | The old driver's `contentHash`; the `single` vector was recomputed independently with .NET SHA-256 |

The proxied run's report equals `reports/morphir-typescript.json` under the parity exclusions, so
the transcript and the report describe the same run.

The Rust adapter's transcript was added in IR-2, recorded on Windows 11 against the adapter at the
parent's current submodule pin. That pin does not change `crates/morphir-mck-adapter`. Two things
make it platform-independent evidence rather than one machine's:

- `mise run mck:parity-rust` recorded the same session on Linux in CI run
  [35470698507](https://github.com/finos/morphir/actions/runs/35470698507), and that recording is
  byte-identical to this file, all 401 760 of them.
- Replaying it reproduces `reports/morphir-rust.json`, captured on Linux at the earlier pin, record
  for record. Both platforms and both revisions agree.

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
