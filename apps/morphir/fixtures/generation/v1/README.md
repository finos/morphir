# Retained-model generation fixtures, version 1

These inputs are handwritten from the existing v4 `Library`, `ExpressionBody`
and `IntegerLiteral` contracts, the engine checkpoint profile, and the existing
MEP `MorphirModel` decoder. `expected.json` freezes the public function `answer`,
its result `42`, the generated module identity and retained unit identities.
Expectations were fixed before observing the new command. The test never
rewrites them from an adapter report.

`model.json` and `model.yaml` describe the same semantic library. `checkpoint.ion`
uses the `morphir_pipeline` engine envelope, retains unit ID `retained-logical`,
and carries annotated metadata, decimal scale, negative zero, blob bytes and
provenance. `mep.ion` uses the distinct `morphir_model` envelope and includes an
unknown enrichment owner. The shared MEP decoder imports the semantic library;
the complete original Ion value is captured in an explicit
`morphir_model_import` provenance event. This capture asserts no authority for
the enrichment owner. A source with both envelope annotations is rejected.

The acceptance helper derives binary *inputs* from these fixed Ion values using
the maintained Ion codec. It checks the actual binary symbols sidecar against
the original Ion values, including metadata and provenance. It does not produce
expected semantics from CLI observations. Text and binary forms must produce
byte-identical sidecars; JSON and YAML must also agree.

## Command use

```sh
morphir generate model.json --target moonbit --output dist --json
morphir generate checkpoint.ion --output dist --backend-option 'naming="readable"'
morphir generate model.yaml --target elm --output elm-out
morphir generate checkpoint.ion --validation required --build-target js \
  --build-provider process --build-helper /absolute/path/library-build.mjs \
  --build-node node --home /absolute/path/moon-home --sdk /absolute/path/morphir-sdk
```

`generate` accepts a retained model. `run` compiles project sources. `--target`
selects the generator, currently `moonbit` or `elm`; `--build-target` selects a
compiler target only under `--validation required`. Source-only is the default
and does not acquire a compiler. Backend options repeat as `key=<JSON>`, reject
duplicate keys, and pass through existing backend validation. MoonBit currently
accepts `naming`; unrecognized options fail.

The output parent directory must already exist. The existing confined publisher
writes the generated project under `<output>/compile.dest/model`. Logical unit
IDs never become output paths. Source diagnostics and report artifact sources
refer to the actual input. Stdin requires an explicit `--model-format`.
Logs default to `.morphir/logs/execution.ionb` in the working directory;
`--log-file` and `--log-format` select the existing local sink. Dry-run does not
open a log or publish files.

MoonBit emits binary `symbols.10n` through the existing generator and byte
publisher. Elm has no rich source-context sidecar, so rich checkpoint or MEP
input fails the shared checked-loss boundary before generation or publication.
Plain semantic JSON/YAML can generate Elm. The same host publisher validates
required builds before replacing an existing publication; rejection, compiler
failure and cancellation preserve existing output.

## Run focused acceptance

```sh
moon build apps/morphir pkgs/morphir-engine/acceptance/retained-generation \
  --target js --target-dir .dev/generation-build
node apps/morphir/scripts/test-generation.ts js
moon build apps/morphir --target native --target-dir .dev/generation-build
node apps/morphir/scripts/test-generation.ts native
```

The aggregate and installed-package lanes can select artifacts without rebuilding
inside the test. `MORPHIR_HEADLESS_BUILD` and `MORPHIR_HEADLESS_PROFILE` select the
build directory and profile, including `release`. `MORPHIR_HEADLESS_BINARY`
selects the exact compiled artifact, including an already admitted native binary.
For Node, `MORPHIR_HEADLESS_LAUNCHER` selects the launcher to execute, including
the installed npm `bin/morphir.js`; the compiled binary is still hashed as
evidence. `MORPHIR_GENERATION_BUILD`, `MORPHIR_GENERATION_PROFILE`,
`MORPHIR_GENERATION_BINARY` and `MORPHIR_GENERATION_LAUNCHER` take precedence over
the corresponding shared settings when supplied.

`MORPHIR_GENERATION_VERIFIER` independently selects the built JS
`retained-generation.js` sidecar verifier, so an aggregate can build it once and
reuse it across CLI targets and package layouts. `MORPHIR_GENERATION_HELPER`
selects the real `library-build.mjs` provider. Installed-package qualification
points this at the installed package's helper. The CLI, launcher and verifier
digests are checked before and after the suite.

The test runs in a temporary home and workspace with no display, generates from
six JSON/YAML/Ion text/Ion binary inputs, compiles Elm with the real compiler,
requires a real MoonBit process-provider build, and builds and invokes a consumer
whose result must be the fixed `42`. It checks default/explicit logs, metadata,
binary bytes, unsupported requests, failed builds, stdin and cancellation.
It records artifact digests and observations under `.dev/generation-evidence/`.
No browser or daemon is involved. The qualified targets are bounded as follows:

| CLI host | Demonstrated generation behavior |
| --- | --- |
| Node | Complete source-only, required build, consumer invocation and refusal suite |
| Native on macOS | Complete source-only, required build, consumer invocation and refusal suite |
| WASI | Help works; generation explicitly refuses missing file/cancellation effects before publication |
| Wasm GC with Node runner | Help works; generation explicitly refuses the existing missing observation clock/log capability before publication |

For portable boundaries, build the corresponding CLI target into the same target
directory, then run `test-generation.ts wasm` or `test-generation.ts wasm-gc`.
The pure shared data suite covers all four targets. These local results do not
qualify Windows/Linux native installations or the complete installed release.
