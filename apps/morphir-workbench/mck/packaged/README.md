# Packaged Workbench codec adapter

This entry facade calls the production `finos/morphir-workbench/mck.handle_line`.
The sibling `packaged-diagnostics` entry adds one response-size diagnostic service.
Both use the same codecs, comparator and observation protocol. The selected
qualification contract is offline Workbench `0.1.0-draft.26`; other contracts in
the linked dispatcher are not newly qualified by this packaging work.

Build from the repository root after installing the pinned tools and core:

```sh
mise run setup:core
mise run package:codec-adapter
```

The task acquires Moon's library dry-run recipe and matching core graph. It
supplies every source package and referenced transitive core asset to the
existing assembly planner/compiler. It executes no commands from the recipe.
Actual compile/link runs with an empty `PATH` and no `MOON_HOME`, using the
packaged compiler. The current JavaScript compiler needs `--stack-size=4096`
while packaging this graph. Consumers use normal Node/Chromium settings.

Publications appear below `.dev/packaged-codec-adapter/bytes-v1` and
`bytes-diagnostics-v1`, each containing `model.wasm` and `manifest.ion`.
`MORPHIR_CODEC_ARTIFACTS` selects another build destination. Publication refuses
an existing destination; choose a fresh root for another build. The complete
graph and concrete compiler/core/SDK pins remain in the Ion manifest even when
linking removes unused code. Registry solving is separate from this explicitly
supplied graph.

## Byte contract

The local draft execution profile has exact identity from
`byteExecutionProfile`, independently of the source language and artifact hash.
The baseline imports `morphir_bytes_v1.input_len`, `input_byte` and `output_byte`;
the diagnostics profile additionally imports
`morphir_diagnostics_v1.response_bytes`. The single export is `handle`.

One request contains at most 3,146,752 strict UTF-8 bytes. One response contains
at most 2,097,152 bytes. A positive return is the exact response byte length;
zero is terminal exit with no output; negative, trap, invalid callbacks or
inconsistent lengths are infrastructure failures. Calls are sequential. The host
copies retained output before releasing the exchange's buffers. Malformed codec
inputs that produce ordinary invalid observations remain recoverable requests.
An infrastructure failure requires a fresh instance.

The loader verifies the saved pair and selected profile before instantiation.
A baseline host refuses the diagnostics profile, and a diagnostics host requires
an explicit service. Profile names and hashes are drafts, not a new MEP or WIT
standard. These are core-Wasm artifacts; they make no Component Model claim.

## Independent MCK qualification

Select the upstream shared runner and independently authored exact draft26 kit:

```sh
MORPHIR_MCK_BIN=/path/to/morphir \
MORPHIR_WORKBENCH_KIT=/path/to/finos/morphir/spec/workbench/mck/draft.26 \
mise run test:codec-adapter-mck
```

The gate compares existing Node/native release adapters and both saved profiles
on fresh Node and real Chromium. The browser bridge transports requests into the
browser; it contains no alternate codec implementation. Every report is
rechecked through the shared runner. Complete records must match the existing
adapters, including refusals and exact numeric/UTF-16/Ion observations.
The gate records actual runner/corpus/artifact/manifest digests, host identities
and browser lifecycle evidence in `.dev/codec-adapter-mck/qualification.ion`.
`MORPHIR_CODEC_EVIDENCE` selects another report directory. Upstream report JSON
remains the exact upstream format, an explicit boundary exception to Ion.

For the normal process bridge, select Node as the shared runner's adapter and
pass `pkgs/morphir-host/embedding/node-byte-adapter-cli.mjs`, the publication
directory and exact profile as its arguments. The bridge preserves NDJSON and
correlation, honors backpressure, refuses incomplete/oversized frames, and
disposes on EOF, exit and failure. Stdout contains only observations. The
diagnostics profile appends events to `.morphir/logs/codec-adapter.jsonl` by
default. An optional final CLI argument selects an explicit log path, which is
honored even outside that default directory. Browser qualification uses an
explicit diagnostic sink to stderr.

The existing shared runner owns deadlines, subprocess termination, corpus
selection, verdicts and report checking. Synchronous foreground Wasm is not
interruptible with an AbortSignal. Direct Wasm loading inside the shared MCK
runner, a shared MEP component binding, installed CLI routing and native
component-host facade gaps remain separate work.

The full HTML specification and task graph are stored in shared beads under
`morphir-ukvn.5.55.7.2` and plan `morphir-ukvn.5.55.7.2.1`.
