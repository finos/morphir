# Proposal

## Why

finos/morphir-gleam publishes the Gleam extension `morphir-gleam` 0.4.0 as a core-Wasm guest for the execution
profile `morphir/mep-bytes-v1/v1-draft` (finos/morphir-gleam#23). The MoonBit CLI cannot run it on the
`core-wasm-process` route, for two reasons:

1. **One document only.** The route sends exactly one source document and always sets `languageId: "moonbit"`.
   A Gleam project is a tree of modules under `src/` that import one another. The guest must get the whole tree in
   one `compileModel` request, with the language from its claims.
2. **MoonBit artifacts only.** The route loads only `model.wasm` with a binary Ion `manifest.ion` of schema
   `morphir-assembly-artifact-v1-draft`. That manifest records a MoonBit package graph, compiler version and core
   and SDK digests. A guest written in Rust cannot fill these fields truthfully. The Gleam bundle has no
   `manifest.ion`. It has a release descriptor (`2.0.0-draft.2`) with `runtime: "core-wasm"`, an
   `executionProfile` and the guest's claims.

The first draft of this change made the `core-wasm-process` route run the Gleam module, as a fast follower of the
worker host change `host-extensions-as-workers`. Since then, main runs every extension command on the worker host
(finos/morphir-moonbit#276 to #280, #284) and retires the `core-wasm-process` route and its Node helper. On main the
CLI already probes the guest, sends the claimed language, refuses a tree without the claim `multiDocument`, offers
the Ion tuple and then the JSON tuple, and runs a WASM module from a contract `0.2.0` pin with no `manifest.ion`.

The Gleam module still does not compile correctly on main, and `generate` is still too strict:

- The CLI names each document relative to the directory that the user gave, so the module names depend on that
  directory. Since finos/morphir-gleam#29, the released Gleam 0.4.0 guest keeps the full path of a relative URI, so
  `compile src` (URI `app/money.gleam`) gives `app/money`; but `compile src/app` sends `money.gleam` and gives the
  module `money`.
- `generate` requires the guest to claim the envelope's tuple, so a Gleam guest that claims only JSON cannot
  generate from an Ion model.
- The CLI has no `--language`, no `--source-base`, no `selection` report object and no ignore files, and it does
  not check the content of a release descriptor.

On 2026-10-31 Damian Reeves decided to cut this change down to the work that main does not do yet, as long as every
requirement in its specs is still met. design.html, "Scope after the worker host", maps each requirement to its
evidence on main or to an open task. The same day he answered the questions about the requirements that did not fit
main (FIT-1, FIT-3, FIT-4 and the first question of FIT-5): the specs use main's error codes, main's interactive
session with one added agreement check, main's skipped directories with ignore files added, and main's contract
`0.2.0` pin for WASM modules on the worker host. He then answered PIN-2: an installed `morphir-bytes-v1` pin must
name its release descriptor, and a local pin may omit it with a warning. He also answered FIT-2: operations from
claims follow main for now, and finos/morphir-moonbit#293 decides the long-term rule. He then answered the
ignore-file questions IGN-1 to IGN-5 and PIN-3: the walk follows Git by default and has a contained mode for
reproducible runs, `.morphirignore` applies only to `morphir extension compile` for now, and the codes of the
descriptor rule stay. He also confirmed that the CLI walks a directory that the user names even when a pattern
above it matches, and filters the entries below it. Two earlier open points are resolved: finos/morphir-gleam#29
makes the Gleam guest keep the full path of a relative URI as the module name, and the release
`extension/gleam/v0.4.0` exists with the attested module and descriptor. design.html still lists two open points
(the decoding of percent-encoded segments and the overlap with the worker host).

## What Changes

The items below are the whole behavior of the change. Each one says what main already does and what is left.

- **Claims before the operation.** Before `compile` or `generate`, the CLI runs a describe-only probe of the pinned
  guest, and the live claims select the language, the source file extensions, the multi-document permission, the
  operation, the model tuple and the generate target. A compile operation is `compile` or `compileModel`, and a
  generate operation is `generate` or `generateModel`, as on main (FIT-2, decided by Damian Reeves, 2026-10-31;
  finos/morphir-moonbit#293 decides the long-term rule). *On main:* the probe, the operation check, the
  multi-document permission and the default target. *Left:* `--language` (several claimed languages without it are
  refused with `extension.input_invalid`), the extensions of the selected language only, tests of the target
  refusals, and the `selection` report object.
- **Model format negotiation.** Without `--model-format`, `compile` offers every model tuple that the CLI
  supports, Ion first, then JSON, and the session uses the first tuple that the guest agrees on. With
  `--model-format`, the CLI offers only that tuple. Only an empty agreement is `extension.tuple_unavailable`
  (design.html, SEL-2). *On main* (finos/morphir-moonbit#284). *Left:* the refusal message names the claimed
  tuples.
- **Agreement check.** The host reads the `initialize` answer before it sends the operation. It compares the
  claims in the answer with the probe (`extension.claims_mismatch`), then requires an agreement of offered tuples
  only, in offer order, whose first tuple is the tuple that the CLI selected from the probe claims
  (`extension.agreement_mismatch`). Both refusals exit 2 and send no operation (FIT-3, decided by Damian Reeves,
  2026-10-31). *On main:* the claims comparison and the offer and order check. *Left:* the check against the probe
  selection, which `generate` needs because the CLI converts the model to the selected tuple before the session.
- **Model conversion for generate.** `generate` offers the envelope's tuple first, then the tuples that the host
  can convert the model to: first those that it can reach without loss, then the others, each in host order. When
  the guest does not claim the envelope's tuple, the host converts the model to the first claimed tuple, so it
  prefers a lossless conversion. Only when the guest claims no offered tuple is the command refused with
  `extension.tuple_unavailable` (design.html, SEL-4). *Left:* all of it.
  - The host library `pkgs/morphir-host` converts, with the engine codec registry
    (`pkgs/morphir-engine/data/registry.mbt`). The CLI, the browser host and the worker host share it.
  - JSON to Ion is always lossless. Ion to JSON is allowed only when it is lossless, unless the user gives the new
    flag `--allow-model-loss` for that one `generate`.
  - Without the flag, a lossy conversion is refused with `data.lossy_conversion`, exit 2, before the operation
    session and with nothing published, as the built-in `morphir generate` does. The message names the flag. With
    the flag, the command exits 0, writes one warning for each kind of dropped data, and the report has
    `conversion: {from, to, dropped}`.
  - The converted model keeps its `modelId`. Its `revision` is `sha256:` and the lowercase hexadecimal SHA-256 of
    the converted payload bytes.
  - The host reports the conversion as an `info` diagnostic with the code `extension.model_converted`, not as a
    file. Its `data` has exactly the members `from`, `to` and `dropped`; `from` and `to` each have exactly
    `profile`, `codec`, `revision` and `payloadSha256`. The diagnostic is in the `diagnostics` of the JSON report
    and is one line on stderr. The report's `conversion` object is equal to its `data`. The host writes no file in
    the output folder for the conversion and does not copy the original bytes (decided by Damian Reeves,
    2026-10-31; this replaces the earlier conversion record `mep/conversion.json`).
- **Source trees.** `compile` accepts a directory and collects the regular files that have an extension the
  selected language claims, in a bounded and sorted snapshot, with no `sources.root`. *On main:* directory input,
  the claimed extensions and no `sources.root`. *Left:* the URI of each document is its path relative to a source
  base (`--source-base`, or else the input directory, so the default URIs do not change), each segment is
  percent-encoded, and documents are sorted by the whole URI in byte order (SRC-1, decided by Damian Reeves,
  2026-11-01).
  - The walk keeps main's skip list: hidden directories, `.git`, `.mooncakes`, `_build`, `node_modules` and
    `.venv` (FIT-4, decided by Damian Reeves, 2026-10-31).
  - It also honors ignore files, in `gitignore` syntax with Git's nesting rules. By default it reads the layers
    that Git reads: in a Git work tree, the global excludes file (`core.excludesFile`, default
    `$XDG_CONFIG_HOME/git/ignore`), `.git/info/exclude` and the `.gitignore` files from the work-tree root down
    through the walked tree; outside a work tree, no `.gitignore` (IGN-2, IGN-3). A Morphir-specific
    `.morphirignore` in each directory is read after the `.gitignore` of that directory, so the last matching
    pattern decides and a `!` pattern in `.morphirignore` can include again a path that `.gitignore` excludes; a
    deeper directory decides over a higher one (IGN-1). `--ignore-mode contained` reads only the ignore files in the
    walked tree, for reproducible runs, and `--skip-ignore-layer` turns off one layer. A file that the user names
    is read even when an ignore file matches it (IGN-5). `.morphirignore` applies only to `morphir extension
    compile` in this change; a separate change makes it project-wide (IGN-4). All decided by Damian Reeves,
    2026-10-31. *Left:* all of it, with the library of moonrockz/moonx-tools#16.
- **Tree limits.** At most 1,024 documents, 1 MiB for each file, 2 MiB of source text in total, a depth of 32
  and 16,384 walked entries. Symbolic links and special files are refused. The framed request must still fit in
  4 MiB. Every source refusal keeps main's code `extension.input_invalid`, exit 2; this change adds no new source
  code (FIT-1, decided by Damian Reeves, 2026-10-31). *On main:* every limit except the 1 MiB file bound, and the
  refusals. *Left:* the 1 MiB bound, and messages that name the limit, the relative path of a link and the URI of
  a file that is not UTF-8.
- **WASM modules without the MoonBit manifest.** *On main:* a contract `0.2.0` pin names the module and its
  runtime; the worker host runs only the bytes that it hashed, and checks the module against
  `morphir-bytes-v1` before instantiation; descriptor claims must equal the live claims. *Left:* the descriptor
  content checks (schema, identity, the single matching artifact, the runtime and execution profile, and every
  `critical` member) and the descriptor `gitCommit` in the report as a claim. The spec describes main's behavior
  for WASM modules on the worker host: one contract `0.2.0` pin with an optional descriptor, a 512 MiB artifact
  bound, and the structure check in the MoonBit worker host, which lowers a larger memory maximum to 4,096 pages
  (FIT-5, decided by Damian Reeves, 2026-10-31). The spec uses main's codes `extension.describe_failed`,
  `extension.digest_mismatch`, `extension.descriptor_invalid` and `extension.pin_invalid` (FIT-1).
  - An installed pin for a `morphir-bytes-v1` module must name its release descriptor, or it is refused with
    `extension.pin_invalid`. A local pin may omit it; the host then runs the module and adds the warning
    diagnostic `extension.descriptor_checks_skipped`, exit 0 (PIN-2 and its codes PIN-3, decided by Damian
    Reeves, 2026-10-31).
    finos/morphir-moonbit#292 explores `morphir trust` for these cases. *Left:* all of it.
- **Acceptance with the real module.** A qualification task runs the released `morphir-gleam` 0.4.0 module (or, as
  the fallback, a build from the pinned finos/morphir-gleam commit of the release) through the npm and native CLI. It compiles a Gleam source tree
  with cross-directory imports and generates Gleam from the result. *Left:* all of it.

## Capabilities

### New Capabilities

- `extensions/claim-selection`: the probe session; how the live claims select language and target; how the CLI
  offers model tuples in preference order and uses the first agreed tuple, or only the tuple that
  `--model-format` requires; how claims and the agreement must match the probe; and how the host converts the
  model for `generate`, with the lossless preference, the loss rules, the `--allow-model-loss` flag, the identity
  of the converted model and the `extension.model_converted` diagnostic.
- `extensions/source-documents`: how `compile` turns a file or a directory into MEP source documents: skipped
  directories and ignore files, URIs, ordering, limits, encoding and the multi-document permission.
- `extensions/core-wasm-modules`: how a WASM module without a MoonBit manifest is pinned with a contract `0.2.0`
  pin, checked against its release descriptor and against the execution profile, and run on the worker host.

### Modified Capabilities

None. `openspec/specs/` holds no main specs yet. `host-extensions-as-workers` defines
`extensions/extension-invocation` and `extensions/wasm-workers` but is not archived. This change does not edit
them. Its requirements are written so that the worker host can keep them (see design.html, "Relation to the
worker host").

## Beads

- **Tracked by**: `morphir-ukvn.5.64.37`
- **Related**:
  - `morphir-ukvn.5.64` (parent: the MoonBit CLI becomes the primary Morphir CLI)
  - `morphir-ukvn.5.64.36` (`host-extensions-as-workers`; its groups 1 to 5 are on main, and this change builds on
    them)
  - `morphir-ukvn.5.64.28` (Gleam compile, generate and roundtrip; it can use this route as its provider)
  - `morphir-ukvn.5.64.30` (installed native qualification; not changed, installed selection stays out of scope)
  - `morphir-ukvn.5.64.34` (`acquire-extensions-from-repositories`, draft; installation of core-Wasm bundles from
    repositories belongs there, not here)
  - `morphir-ukvn.1.4` (moving the Gleam extension to finos/morphir-gleam)
- **Related outside beads**:
  - finos/morphir-gleam#31 (host test: the host offers the Ion tuple first and the JSON tuple second, and the
    `morphir-gleam` 0.4.0 guest agrees on JSON and compiles)
  - finos/morphir#1115 (merged): the matching MEP text in `spec/mep/model-transport.md`, the offer order and the
    host conversion for `generateModel`; its follow-up is bead `morphir-hv6m` (MCK checks of the selection order and
    the conversion); this change does not edit finos/morphir
  - finos/morphir-moonbit#283 (merged): aligns the "Model tuple negotiation" requirement of
    `host-extensions-as-workers` with SEL-2 and uses `extension.agreement_mismatch` in the same way
  - finos/morphir-moonbit#288 (merged): replaces the open question about the `generate` conversion in
    `host-extensions-as-workers` with a note that points to SEL-4 of this change
  - moonrockz/moonx-tools#16: the reusable ignore-file library and moonx tool (Git-compatible by default, custom
    ignore files, layer and containment switches, explain mode); task 2.6 depends on it
  - finos/morphir-moonbit#293 and finos/morphir#1121 (task graph): the follow-up change that makes
    `.morphirignore` project-wide covers them

## Impact

- **Code:** `apps/morphir/cli/extension.mbt` (`--language`, `--source-base`, the URIs, messages and ignore files of
  `extension_sources`, the `generate` offer in `extension_generate_offer`, the `--allow-model-loss` flag, the
  `extension.model_converted` diagnostic, the descriptor content checks and the `selection` and `conversion` report
  objects), the model conversion in `pkgs/morphir-host`, the tuple names in the `extension.tuple_unavailable`
  message and the agreement check against the selected tuple in `pkgs/morphir-host/worker`, the descriptor rule for
  `morphir-bytes-v1` pins, the `--ignore-mode` and `--skip-ignore-layer` options, a dependency on the ignore-file
  library of moonrockz/moonx-tools#16, and `apps/morphir/docs/extension.md`. The Node embedding host and the build-provider helper
  do not change: main no longer uses them for extension commands.
- **Pins:** the shape of a contract `0.2.0` pin does not change.
- **Users:** a `generate` whose envelope tuple the guest does not claim now converts the model, or fails with
  `data.lossy_conversion` (exit 2) when every conversion would lose data and the user did not give
  `--allow-model-loss`, instead of failing with `extension.tuple_unavailable`. A converting `generate` reports an
  `extension.model_converted` info diagnostic and adds no file to the output. A directory compile names each
  document relative to the named directory, as before, so `compile src` sends `app/money.gleam`; with
  `--source-base /work/shop`, `compile /work/shop/src/app` sends `src/app/money.gleam`. A
  directory compile does not read the files that Git ignores (global excludes, `.git/info/exclude` and the
`.gitignore` files from the work-tree root down) or that a `.morphirignore` ignores; `--ignore-mode contained`
reads only the ignore files in the tree. A guest
  that claims several languages needs `--language`. Source refusals keep `extension.input_invalid` and exit 2. A
  guest whose first agreed tuple is not the tuple selected from its probe claims is now refused with
  `extension.agreement_mismatch`, exit 2. A local pin for a `morphir-bytes-v1` module without a descriptor runs with
  an `extension.descriptor_checks_skipped` warning. The compile offer, the other codes and the pin are as on main.
- **Qualification:** one new opt-in task, `test:portable-mep-gleam`. It is not added to routine PR CI and adds no
  macOS or Windows job.
- **Other repositories:** this change edits none. Task 2.6 depends on the ignore-file library that
  moonrockz/moonx-tools#16 delivers in its own repository. The acceptance task reads the finos/morphir-gleam release
  `extension/gleam/v0.4.0`, or as the fallback builds the module from the pinned commit `191a35e`.
