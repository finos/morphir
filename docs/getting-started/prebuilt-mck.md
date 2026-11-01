---
id: prebuilt-mck
title: Prebuilt MCK backend
sidebar_label: Prebuilt MCK backend
sidebar_position: 6
---

# Prebuilt MCK backend

Use the `finos/morphir` CLI as a pinned MCK backend for another CLI or binding.
The executable contains the shared runner and independent report checkers.
Running them requires no Rust compiler, Cargo, or Morphir source build. An
adapter still needs its declared runtime, such as Node.js, or its own native
executable.

These instructions target `v0.4.0-beta.12`. Download its assets after the
[release](https://github.com/finos/morphir/releases/tag/v0.4.0-beta.12) is published.
Use the release receipt to pin the source commit and per-platform archive
SHA-256 in your own dependency configuration. A version, source commit, and
archive digest identify different inputs; retain all three.

## Download into a private backend directory

Both the MoonBit CLI and this backend are named `morphir`. Give the backend an
explicit private path and set `MORPHIR_MCK_BIN` to that path.

| System | Processor | Archive |
| --- | --- | --- |
| Linux | x86-64 | `morphir-0.4.0-beta.12-x86_64-unknown-linux-gnu.tgz` |
| Linux | ARM64 | `morphir-0.4.0-beta.12-aarch64-unknown-linux-gnu.tgz` |
| macOS | Intel | `morphir-0.4.0-beta.12-x86_64-apple-darwin.tgz` |
| macOS | Apple silicon | `morphir-0.4.0-beta.12-aarch64-apple-darwin.tgz` |
| Windows | x86-64 | `morphir-0.4.0-beta.12-x86_64-pc-windows-msvc.zip` |
| Windows | ARM64 | `morphir-0.4.0-beta.12-aarch64-pc-windows-msvc.zip` |

Each archive has a companion `<archive>.sha256` asset. For example, on Apple
silicon, download and check before extracting:

```sh
set -eu
version=0.4.0-beta.12
target=aarch64-apple-darwin
backend="$HOME/.local/share/morphir/backends/$version/$target"
archive="morphir-$version-$target.tgz"
release="https://github.com/finos/morphir/releases/download/v$version"
mkdir -p "$backend"
curl --fail --location "$release/$archive" --output "$backend/$archive"
curl --fail --location "$release/$archive.sha256" --output "$backend/$archive.sha256"
(
  cd "$backend"
  shasum -a 256 -c "$archive.sha256"
) && tar -xzf "$backend/$archive" -C "$backend"
export MORPHIR_MCK_BIN="$backend/morphir"
"$MORPHIR_MCK_BIN" --no-banner version
```

On Linux, select the appropriate `unknown-linux-gnu` target and use
`sha256sum -c` in place of `shasum -a 256 -c`. Linux packages target GNU/Linux,
not musl. Use a native package for the operating system and architecture you
run; the platform matrix does not imply support for every OS or C-library
version.

On Windows PowerShell:

```powershell
$ErrorActionPreference = 'Stop'
$version = '0.4.0-beta.12'
$target = 'x86_64-pc-windows-msvc' # or aarch64-pc-windows-msvc
$backend = "$env:LOCALAPPDATA\Morphir\backends\$version\$target"
$archive = "morphir-$version-$target.zip"
$release = "https://github.com/finos/morphir/releases/download/v$version"
New-Item -ItemType Directory -Force -Path $backend | Out-Null
Invoke-WebRequest "$release/$archive" -OutFile "$backend\$archive"
Invoke-WebRequest "$release/$archive.sha256" -OutFile "$backend\$archive.sha256"
$expected = (Get-Content "$backend\$archive.sha256").Split()[0]
$actual = (Get-FileHash "$backend\$archive" -Algorithm SHA256).Hash
if ($actual -ne $expected) { throw 'Archive checksum mismatch' }
Expand-Archive "$backend\$archive" -DestinationPath $backend
$env:MORPHIR_MCK_BIN = "$backend\morphir.exe"
& $env:MORPHIR_MCK_BIN --no-banner version
```

The downloaded checksum detects damaged or changed downloads. For repeatable
automation, also compare it with the exact archive hash recorded in the final
release receipt, then keep that expected value in your dependency lock. Retain
the executable hash as well when recording a run.

## Pin the canonical Workbench corpus

Workbench kits are explicit data directories containing `cases.json`.
`mck kit vendor` manages the **IR** kit; it does not vendor Workbench kits.
For Workbench, extract the canonical data from the parent repository at the
full source commit recorded in the release receipt. No submodules or source
compilation are needed.

Set `MORPHIR_KIT_REVISION` to that full 40-character lowercase commit SHA, then:

```sh
set -eu
: "${MORPHIR_KIT_REVISION:?Set the full release source commit from the receipt}"
kit_root="$HOME/.local/share/morphir/kits/$MORPHIR_KIT_REVISION"
mkdir -p "$kit_root"
curl --fail --location \
  "https://codeload.github.com/finos/morphir/tar.gz/$MORPHIR_KIT_REVISION" \
  --output "$kit_root/parent-source.tgz"
tar -xzf "$kit_root/parent-source.tgz" -C "$kit_root" --strip-components=1 \
  "morphir-$MORPHIR_KIT_REVISION/spec/workbench"
export MORPHIR_WORKBENCH_KIT="$kit_root/spec/workbench/mck/draft.29"
printf '%s  %s\n' \
  '27dd83719a5a30075bb37041fe78e71e1c782a06b812fc49ab9ab83d08f07ac8' \
  "$MORPHIR_WORKBENCH_KIT/cases.json" | shasum -a 256 -c -
```

Use `sha256sum -c -` for the last command on Linux. Windows users can extract
the same commit archive with `tar`, set `$env:MORPHIR_WORKBENCH_KIT` to its
`spec\workbench\mck\draft.29` directory, and compare `Get-FileHash` with the
digest above. Preserve kit bytes, including line endings; if vendoring them
into Git, mark the directory `-text` in `.gitattributes`.

The exact `0.1.0-draft.29` local-model kit has 32 independently authored cases.
Its `cases.json` SHA-256 is
`27dd83719a5a30075bb37041fe78e71e1c782a06b812fc49ab9ab83d08f07ac8`.
Its expectations cite authority revision
`2b0cb1d64ccd0455aba3eaa2b143dbc7d276df70`; this describes their origin and
does not replace the release source pin. The kit checks `inspect-model` and
`export-model-original` against captured JSON, YAML, Ion text and Ion binary
bytes over JSON adapter transport. It covers normalized IR, exact original
bytes and specified refusals. The local offline profile does not qualify an
authenticated or connected model service.

## Run an explicit adapter, then check its saved report

Select an adapter implementing the exact kit contract. For a prepared Node
adapter, set `MORPHIR_MCK_ADAPTER` to its absolute JavaScript path and
`MORPHIR_MCK_NODE` to its Node executable:

```sh
set -eu
: "${MORPHIR_MCK_ADAPTER:?Set the absolute adapter path}"
: "${MORPHIR_MCK_NODE:?Set the Node executable for the adapter}"
mkdir -p evidence
"$MORPHIR_MCK_BIN" --no-banner mck workbench run \
  --kit "$MORPHIR_WORKBENCH_KIT" \
  --adapter "$MORPHIR_MCK_NODE" --adapter-arg "$MORPHIR_MCK_ADAPTER" \
  --report evidence/workbench-draft29.json \
  --timeout 35000 --session-timeout 180000
"$MORPHIR_MCK_BIN" --no-banner mck workbench check \
  --kit "$MORPHIR_WORKBENCH_KIT" \
  --report evidence/workbench-draft29.json
```

A native adapter instead uses `--adapter /absolute/path/to/adapter` with its
own arguments. The runner launches it directly without a shell. Treat either
command's nonzero exit as failure: qualified results return 0, qualification
or operational failures return 1, and usage errors return 2. Run checking as
a separate step even when the report claims `qualified: true`. It reloads
the pinned corpus and recomputes the verdicts, rejecting malformed reports,
altered observations, missing or reordered records, and mismatched corpus
digests. A valid report is consistency evidence, not proof of its producer's
identity.

MoonBit's `apps/morphir/scripts/test-headless-model-mck.ts` consumes
`MORPHIR_MCK_BIN` and its own frozen copy of these exact 32 cases. That script
does not read `MORPHIR_WORKBENCH_KIT`. Its JS/native qualification adds five
altered-report refusals, a one-MiB original-byte control and a frame exceeding
three MiB. Preparing the consumer CLI, framing helper and adapter requires
MoonBit, Node and Bun; invoking the prepared shared runner requires no Rust
toolchain.

## Keep profiles independently versioned

This backend accepts these exact Workbench contract versions, with no fallback
to a nearby draft:

`0.1.0-draft.1`, `0.1.0-draft.2`, `0.1.0-draft.3`, `0.1.0-draft.4`,
`0.1.0-draft.5`, `0.1.0-draft.11`, `0.1.0-draft.12`, `0.1.0-draft.14`,
`0.1.0-draft.15`, `0.1.0-draft.16`, `0.1.0-draft.17`, `0.1.0-draft.18`,
`0.1.0-draft.19`, `0.1.0-draft.20`, `0.1.0-draft.21`, `0.1.0-draft.22`,
`0.1.0-draft.23`, `0.1.0-draft.24`, `0.1.0-draft.25`, `0.1.0-draft.26`,
`0.1.0-draft.27`, `0.1.0-draft.28`, and `0.1.0-draft.29`.
There is no claim for omitted drafts. Select each historical profile's
own corpus directory. In particular, draft.28 artifact-server and
draft.28 artifact-client use separate `draft.28` and `draft.28/client` kits.
Runner support does not mean an adapter implements every profile or that its
passing report qualifies another runtime or platform.

IR reports, package contracts and MEP profiles have their own versions and
commands. For an IR managed snapshot at the same pinned source revision:

```sh
"$MORPHIR_MCK_BIN" --no-banner mck kit vendor \
  --source github:finos/morphir --revision "$MORPHIR_KIT_REVISION" \
  --dest vendor/morphir-ir-mck
"$MORPHIR_MCK_BIN" --no-banner mck kit status \
  --kit vendor/morphir-ir-mck --json
```

Commit the generated `mck-kit.lock.json` and its listed files. Record its
`snapshotDigest`; repeat acquisitions can require that value with
`--expect-digest`. This managed IR file-map digest is distinct from the plain
SHA-256 of a Workbench `cases.json`. See the
[kit contract](https://github.com/finos/morphir/blob/main/spec/mck/kit-manifest.md)
and [CLI contract](https://github.com/finos/morphir/blob/main/spec/mck/cli-contract.md)
for IR, package and MEP command details.

## Separate MCK from live-host and fixture dependencies

The regular CLI also provides `ui --no-open` and the explicit
`ui --preview-model-originals` preview. A consumer can select this private
executable for a live authenticated host or model-originals host, after
qualifying the required host behavior on its platform.

MoonBit's existing `scripts/headless-host.mbtx` builds a pinned Rust CLI for
three roles: live host, model-originals host and MCK runner. It separately
builds the Cargo test executable `ui_artifact_process` as an artifact producer.
That test executable is not included in the CLI release archives. Replacing
`MORPHIR_MCK_BIN` removes the MCK source-build requirement; the current broader
headless workflow retains its separate host and artifact-fixture preparation
until its caller adopts suitable prebuilt inputs. Do not infer full headless
or connected support from a passing local-model report.
