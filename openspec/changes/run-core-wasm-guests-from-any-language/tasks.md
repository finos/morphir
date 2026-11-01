# Tasks

The worker host on main (finos/morphir-moonbit#276 to #280, #284) already does part of this change. A task marked
`[x]` is done on main at `af16f0be`, and the named test proves it. The open tasks are what is still to do. The table
"Scope after the worker host" in design.html maps every requirement to its evidence on main or to its task, and says
why tasks were removed. Damian Reeves answered FIT-1 to FIT-5, PIN-2, the ignore-file questions IGN-1 to IGN-5 and
PIN-3 (the codes of task 3.6) on 2026-10-31; the specs and the tasks below follow those answers. Group 5 applied the
last of them.

Group 1 delivers the claim selection and the `generate` conversion. Group 2 delivers source trees. Group 3 delivers
the remaining descriptor checks. Group 4 runs the real Gleam module through all of them.

## 1. Claims, tuple selection and conversion (morphir-ukvn.5.64.37.1)

- [x] 1.1 Decode `capabilities.frontend.multiDocument` into `Claims` in `pkgs/morphir-host/worker` (INT-2). Done on
  main: `pkgs/morphir-host/worker/claims.mbt:133-160`; test `claims read the frontend capability flags; an absent
  flag is false` (`claims_test.mbt:215`)
- [x] 1.2 Run a describe-only probe before `compile` and `generate` and decode the claims with
  `Claims::from_describe` (SEL-1). Done on main: `apps/morphir/cli/extension.mbt:1409-1416`; tests `compile on the
  model line publishes the model and reports the session` (`extension_session_wbtest.mbt:362`, method order) and
  `probe of a guest that does not describe: describe_failed and no claims` (`host_driver_test.mbt:127`). The spec
  uses main's code `extension.describe_failed` (FIT-1)
- [x] 1.3 Select the language from the claims (SEL-3): add `--language` through the command-line parsing library,
  refuse several claimed languages without it with `extension.input_invalid` (exit 2, the message names the
  languages; no new code, FIT-1), refuse an unclaimed language with `extension.capability_unavailable`, and collect
  only the file extensions of the selected language. Replace the first-covering-language rule of `extension_language`
  (`apps/morphir/cli/extension.mbt:428`) and the all-languages list of `extension_claimed_extensions` (`:412`);
  verify the "Language from claims" scenarios in `extension_wbtest.mbt` and `extension_session_wbtest.mbt`.
  Done: `extension_language` and `ExtensionInputs::read` in `apps/morphir/cli/extension.mbt`; tests `language from
  claims: the only language, the one that --language names, or a refusal` (`extension_wbtest.mbt`) and `language
  from claims: a guest with several languages needs --language` (`extension_session_wbtest.mbt`)
- [ ] 1.4 Add tests for the target selection that `extension_target` (`apps/morphir/cli/extension.mbt:789`)
  already does (SEL-3): several claimed targets without `--target` are refused, and an unclaimed `--target` exits 2
  with `extension.capability_unavailable` and starts no operation session; verify the "Unclaimed target" scenario
  (the default target is proved by `an unsuccessful answer and a failed shutdown publish nothing`,
  `extension_session_wbtest.mbt:1144`)
- [x] 1.5 Offer every supported compile tuple, Ion first, use the first agreed tuple, and offer only the required
  tuple with `--model-format` (SEL-2). Done on main (finos/morphir-moonbit#284): `extension_compile_offer`
  (`apps/morphir/cli/extension.mbt:607`), `Offer::select` and `ModelOperation::host_tuples`
  (`pkgs/morphir-host/worker/negotiation.mbt:59-110`); tests `an operation that the extension does not claim is
  refused before any call` (`extension_wbtest.mbt:386`), `model tuple negotiation: the CLI offers Ion, then JSON,
  and a JSON-only guest compiles with JSON` (`extension_session_wbtest.mbt:499`) and `required model tuple:
  --model-format json offers only JSON, which an Ion-only guest refuses` (`extension_session_wbtest.mbt:540`)
- [ ] 1.6 Name the claimed tuples in the `extension.tuple_unavailable` message of `Offer::select`
  (`pkgs/morphir-host/worker/negotiation.mbt:97-103`) for the default and the required offer (SEL-2); verify the
  "Guest that claims no offered tuple" and "Explicit Ion with a JSON-only guest" scenarios, and that the worker
  tests still pass on all four targets
- [ ] 1.7 Replace the one-tuple offer of `extension_generate_offer` (`apps/morphir/cli/extension.mbt:631`, "the
  host does not convert a model to another tuple"): offer the envelope's tuple first, then the tuples that the host
  library can convert the model to without loss, in host order, then the tuples that it can reach only with loss,
  in host order; select the first offered tuple that the probe claims, and refuse an empty selection with
  `extension.tuple_unavailable` before the operation session (SEL-2, SEL-4; lossless preference decided by Damian
  Reeves, 2026-10-31); verify the "Generate offer from the envelope" and "Prefer a lossless conversion" scenarios
  with the in-memory workers of `extension_session_wbtest.mbt`, and a unit test with a host order in which the
  first convertible tuple is lossy and a later claimed tuple is lossless
- [ ] 1.8 Add the model conversion to the host library `pkgs/morphir-host`, with the engine codec registry
  (`pkgs/morphir-engine/data/registry.mbt`) and no other converter (SEL-4, A to C): JSON to Ion always lossless,
  Ion to JSON with a loss check that names each dropped kind (`metadata`, `provenance`, `annotations`) and refuses
  with `data.lossy_conversion` unless loss is allowed, the same `modelId`, the revision `sha256:<lowercase hex>` of
  the converted payload, the `from`, `to` and `dropped` value of the conversion diagnostic, and a loss check that
  the offer of task 1.7 can run for each tuple before the operation session; verify unit tests for both directions,
  each dropped kind, a lossless Ion model, the revision text and a deterministic second run, on all four targets,
  and the "One conversion in the host library" scenario
- [ ] 1.9 Use the host conversion in `morphir extension generate` before the operation session, and add the flag
  `--allow-model-loss` through the command-line parsing library, scoped to that one command (SEL-4, B and D):
  without the flag a lossy conversion exits 2 with `data.lossy_conversion`, `committed: []` and a message that names
  the flag; with the flag the command exits 0, writes one stderr warning for each dropped kind, and the JSON report
  has `conversion: {from, to, dropped}`; verify the "Host conversion for generate", "Identity of a converted
  model", "Conversion follows the loss rules" and "Explicit permission to lose model data" scenarios with the
  in-memory workers, in default and `--json` mode, with stdout parseable and
  warnings only on stderr
- [ ] 1.10 Add the `extension.model_converted` diagnostic to the diagnostics of `morphir extension generate` when a
  conversion runs: severity `info`, a message that names both tuples, and `data` with exactly `from`, `to` and
  `dropped`, with `profile`, `codec`, `revision` and `payloadSha256` in `from` and `to`; write it as one stderr
  line through the existing diagnostic output; make `result.conversion` the same value; write no file for the
  conversion in the output folder and keep the guest's retention sidecars as returned (SEL-4, E; decided by Damian
  Reeves, 2026-10-31); verify the "Conversion diagnostic", "Conversion diagnostic data", "Conversion reported on
  stderr, not in the output" and "Report records the conversion" scenarios with the in-memory workers, in default
  and `--json` mode: the exact `data` members, `dropped: []` without the flag, the diagnostic after a guest failure,
  one stderr line, stdout parseable, and an output folder with only the guest's paths
- [ ] 1.11 Add the `selection` object to the report: the language ID, the source file extensions, the model tuple
  or target, and the probe outcome; verify the "Report records the selection" scenario and that the existing
  report fields of `extension_session_wbtest.mbt` are unchanged
- [ ] 1.12 Document in `apps/morphir/docs/extension.md`: `--language` and its `extension.input_invalid` refusal,
  the `selection` report object, the tuples in the `extension.tuple_unavailable` message, and the SEL-4 conversion in
  place of "Generate on the model line offers and sends the envelope's own tuple" (the offer, `--allow-model-loss`,
  its warnings, the `conversion` report object, and the `extension.model_converted` diagnostic and its `data`
  members). The
  probe, the preference order and `extension.agreement_mismatch` are documented on main already; verify the
  documented commands run as written
- [ ] 1.13 Require the first agreed tuple to be the tuple that the CLI selected from the probe claims (FIT-3,
  decided by Damian Reeves, 2026-10-31): give the session the selected tuple, which is the first offered tuple that
  the probe claims for the operation, and refuse an `initialize` agreement whose first tuple is another tuple with
  `extension.agreement_mismatch`, exit 2, before the operation is sent (`agreement`,
  `pkgs/morphir-host/worker/session.mbt:538-560`); keep the claims comparison of `compare_claims` before it. For
  `generate`, the selected tuple is the tuple of task 1.7, so the session sends the converted envelope only when the
  guest agrees on it. Verify the "Session uses the first agreed tuple" scenarios with unit tests in
  `session_test.mbt` (an agreement that skips the selected tuple, an agreement on an unclaimed tuple, and a
  converted generate) and with the in-memory workers of `extension_session_wbtest.mbt` (exit 2, no operation sent,
  no output directory), on all four targets; add the rule to "What one command does", step 3, in
  `apps/morphir/docs/extension.md`

## 2. Source trees as relative-URI documents (morphir-ukvn.5.64.37.2)

- [x] 2.1 Give `extension_sources` (`apps/morphir/cli/extension.mbt:509`) the refusals and the order of the spec
  (SRC-2), all with main's code `extension.input_invalid` and exit 2 (FIT-1, decided by Damian Reeves, 2026-10-31;
  no new source codes): a new 1 MiB bound for one file, a message that names each limit and its value, the
  relative path in the message for a link or a special file, a duplicate URI refused, the URI in the message for
  text that is not UTF-8, and documents sorted by the whole URI in byte order instead of by name in each directory;
  keep main's skip list (FIT-4) and the 4 MiB framed request check of `Call::make`
  (`pkgs/morphir-host/worker/negotiation.mbt:320-337`) last; verify the updated tests in `extension_wbtest.mbt`
  ("Tree limits", "Links and special files", "UTF-8 source text", "Skipped directories" and "Deterministic order"
  scenarios) with generated trees in a temporary directory, including a first test for text that is not UTF-8.
  Done: `extension_sources` and `extension_source_order`; tests `the source snapshot enforces its file, byte, entry
  and depth limits`, `the default limits refuse 1,025 documents and a file larger than 1 MiB`, `text that is not
  UTF-8 is refused with the URI of the file`, `a symbolic link in the sources is refused with its relative path`,
  `documents are sorted by the whole URI in byte order, and a repeated URI is refused` and `the source walk skips
  hidden, build and dependency directories` (`extension_wbtest.mbt`), and `a tree of 1,025 documents is refused
  before any operation session` (`extension_session_wbtest.mbt`)
- [x] 2.2 Make each URI relative to the source base, add `--source-base` through the command-line parsing library,
  and encode each segment as an RFC 3986 path segment instead of refusing names with `:` or `\` (SRC-1, SRC-3);
  keep the single-file rule of `extension_document_uri` (`apps/morphir/cli/extension.mbt:393`) without
  `--source-base`; verify the "Relative document URIs", "Safe URI segments" and "Single file input" scenarios.
  Without `--source-base`, a directory input is its own base (option B, decided by Damian Reeves, 2026-11-01,
  because the current directory broke the published Elm `0.5.0-preview.2` and Python `0.4.2` extensions in the
  extension qualification suite). Done: `ExtensionSourceBase::segments`, `extension_uri_segment` and
  `extension_document_uri`; tests `the source base gives each URI its path relative to the base`, `a tree has URIs
  from the input directory, or from --source-base when given`, `URI segments are percent-encoded and plain names
  stay the same` and `document identities keep relative nesting and never expose absolute host paths`
  (`extension_wbtest.mbt`), and `relative document URIs: a tree is named from the input directory or the source
  base, with no sources.root` (`extension_session_wbtest.mbt`)
- [x] 2.3 Accept a directory for `compile` and refuse more than one document without the multi-document claim.
  Done on main: `extension_sources` (`apps/morphir/cli/extension.mbt:509-605`) and `extension_document_count`
  (`:456`); tests `compile selects sources by the claimed file extensions and sends the claimed language`
  (`extension_wbtest.mbt:240`) and `Python 0.4.1 with two modules: a frontend without multiDocument is refused`
  (`extension_session_wbtest.mbt:588`)
- [x] 2.4 Add tests that two compiles of the same tree give byte-identical `compileModel` requests, and that the same
  package and options with different trees give the same `contextDigest` (the digest code is
  `extension_compile_params`, `apps/morphir/cli/extension.mbt:853-863`); verify the "Same tree twice" and "Same
  options, different trees" scenarios. Done: test `same tree twice gives byte-identical compileModel requests;
  other trees keep the contextDigest` (`extension_session_wbtest.mbt`), which compares the encoded request bytes
- [x] 2.5 Document the source base, the URI encoding, the limits and their messages, and the advice to give
  `--source-base` for a directory below the root of the module paths in `apps/morphir/docs/extension.md` ("What
  one command does", step 4); verify the examples with the in-memory workers. The documentation of the ignore
  files moved to task 2.6. Done: step 4 and the section "Source trees and document URIs"; the examples are the
  trees of `relative document URIs: a tree is named from the input directory or the source base, with no
  sources.root` and `a tree has URIs from the input directory, or from --source-base when given`
- [ ] 2.6 Honor ignore files in the source walk (FIT-4 and IGN-1 to IGN-5, decided by Damian Reeves, 2026-10-31).
  Depends on moonrockz/moonx-tools#16: use its ignore-file library (in place of the earlier candidate
  `moonbit-community/ignore`) and do not start the walk change until a release of it builds for the four targets.
  By default, follow Git: in a Git work tree, read the global excludes file (`core.excludesFile`, else
  `$XDG_CONFIG_HOME/git/ignore`, else `$HOME/.config/git/ignore`), `.git/info/exclude` and the `.gitignore` files
  from the work-tree root down through the walked tree, and outside a work tree no `.gitignore`. Read a
  `.morphirignore` in the same directories, after the `.gitignore` of each directory. Keep Git's precedence (the
  last match decides, a deeper directory decides over a higher one, no re-inclusion below an excluded parent),
  bound each ignore file to 1 MiB, apply main's skip list first, and skip ignored entries before the link and
  special-file check. Filter only the entries below the input: read a named file, and walk a named directory, even
  when a pattern matches it. Add `--ignore-mode <git|contained>` (contained reads only the ignore files in the
  walked tree, in or outside a work tree) and the repeatable `--skip-ignore-layer <global|info-exclude|above>`,
  with `extension.input_invalid`, exit 2, for an unknown value, and document both in the command help and the
  ignore files in `apps/morphir/docs/extension.md` ("Source trees and document URIs"). Verify the
  scenarios of "Ignore files in the source walk", "Precedence of ignore files", "Git ignore layers", "Ignore layer
  switches", "Contained ignore mode", "Ignore files filter only the walk", the ignore part of "Directory input" and
  "Two machines in contained mode" with generated trees in `extension_wbtest.mbt` (a temporary work tree, a
  temporary `XDG_CONFIG_HOME` and `.git/info/exclude`, never the user's own Git configuration), and compare the
  ignored set with `git check-ignore` on the same fixtures where Git is available. The qualification run of task
  4.3 uses `--ignore-mode contained`. `.morphirignore` applies only to `morphir extension compile` (IGN-4); the
  project-wide rule is a separate change (design.html, "Follow-up changes")

## 3. Descriptor checks for WASM modules (morphir-ukvn.5.64.37.3)

- [ ] 3.1 Check the content of a pinned release descriptor in `extension_descriptor`
  (`apps/morphir/cli/extension.mbt:1098`), or in a pure decoder in `pkgs/morphir-host/worker` that the CLI calls
  (INT-1): `schemaVersion` `2.0.0-draft.2`, the descriptor `extensionId` and `version` against the live claims, a
  single matching artifact with a `filename` that has no path separator, its runtime and `executionProfile`
  against the pin's runtime, and every `critical` member, refusing an unknown one by name, all with main's code
  `extension.descriptor_invalid` (FIT-1); verify the "Descriptor
  content" and "Critical members" scenarios with unit tests and the existing `a bad descriptor is refused before
  any worker starts` (`extension_session_wbtest.mbt:1040`)
- [x] 3.2 Read the descriptor with a 1 MiB bound and check its digest before decoding it, before any worker starts.
  Done on main: `apps/morphir/cli/extension.mbt:1098-1120`; test `a bad descriptor is refused before any worker
  starts` (`extension_session_wbtest.mbt:1040`). The spec uses main's code
  `extension.digest_mismatch` (FIT-1)
- [x] 3.3 Compare the descriptor claims with the probe claims before the operation session (INT-2). Done on main:
  `extension_descriptor_matches` (`apps/morphir/cli/extension.mbt:1155`); test `descriptor claims that differ from
  the live describe exit 2` (`extension_session_wbtest.mbt:1001`)
- [ ] 3.4 Report the descriptor digest, the module digest and the descriptor `gitCommit` under the report's
  `worker` object with `origin: "claimed"` (INT-2); verify the "Report origin" scenario and that the existing
  `worker` fields are unchanged
- [ ] 3.5 Document the descriptor content checks and the claimed origin in `apps/morphir/docs/extension.md` ("The
  pin"); verify a pin and descriptor written from the documentation are accepted
- [ ] 3.6 Require the release descriptor for an installed `morphir-bytes-v1` pin and warn for a local pin without
  one (PIN-2, option C, decided by Damian Reeves, 2026-10-31): give the decoded pin its source (local from
  `--extension-pin` or `MORPHIR_EXTENSION_PIN`, installed from the installed extension catalog); refuse an
  installed `morphir-bytes-v1` pin with no descriptor with `extension.pin_invalid`, exit 2, a message that names
  `descriptor`, and no worker started; for a local `morphir-bytes-v1` pin with no descriptor, run the module and add
  the `warning` diagnostic `extension.descriptor_checks_skipped` to the report diagnostics and as one stderr line,
  naming the three skipped checks (the digest against the published release, the critical `runtime` and
  `executionProfile` members, the published claims). A module is `morphir-bytes-v1` when the pin's `abi` says so
  or the worker host classifies it so. Main does not yet run installed extensions (morphir-ukvn.5.64.30), so prove
  the installed refusal with unit tests of the pin check and use it when installed selection joins invocation.
  Verify the "Descriptor for a morphir-bytes-v1 pin" scenarios: the in-memory workers of
  `extension_session_wbtest.mbt` for a local pin with and without a descriptor, in default and `--json` mode
  (stdout parseable, the warning on stderr and in `diagnostics`), and a unit test for the installed pin; document
  the rule in `apps/morphir/docs/extension.md` ("The pin"). finos/morphir-moonbit#292 explores `morphir trust` for
  these cases

## 4. Qualify the morphir-gleam 0.4.0 module (morphir-ukvn.5.64.37.4)

- [ ] 4.1 Add the fixture tree `apps/morphir/fixtures/gleam-tree/` with cross-directory imports and one file name
  with a space, and its expected payload for the module of the release `extension/gleam/v0.4.0` (SHA-256
  `12349dacb1696fee320ce7104001a0d036e3830b9e1e9e26703b36d9e27d205e`); verify the fixture compiles with the
  released module
- [ ] 4.2 Add `scripts/portable-mep-gleam.mbtx` and the mise task `test:portable-mep-gleam` with the two explicit
  bundle inputs (the downloaded `extension/gleam/v0.4.0` release directory, or as the fallback a build from the
  pinned finos/morphir-gleam commit `191a35e`, the commit of the release tag) and no silent choice (ACC-1); the
  script writes a
  contract `0.2.0` pin with a `wasm` runtime and the bundle's descriptor; verify it fails with a clear message when
  neither input is given
- [ ] 4.3 Run compile (with no `--model-format`, so that it agrees on JSON, and with `--ignore-mode contained`) and
  generate through the npm and native CLI with the released module, and the refusal cases of ACC-1, including an explicit `--model-format ion`;
  verify the evidence in `.dev/portable-mep-gleam`, including the probe time and the compile time
- [ ] 4.4 Get a build-master review of where the qualification task runs (no routine PR CI, no new macOS or
  Windows job); verify the decision is recorded in the pull request
- [ ] 4.5 Record the receipt with the module and descriptor digests and the platform as a comment on the epic
  bead, and add a note to `morphir-ukvn.5.64.28` that this route can serve as its provider; verify both comments
  exist

## 5. Answers to the last open questions (morphir-ukvn.5.64.37)

- [x] 5.1 Apply Damian Reeves's answers to IGN-1 to IGN-5 (ignore files) and PIN-3 (the codes of task 3.6) of
  design.html: rewrite the requirements and scenarios that an answer changes, and add or change the tasks that
  implement them. Done in this update: "Only ignore files in the tree" is replaced by "Git ignore layers", "Ignore
  layer switches" and "Contained ignore mode"; "Ignore files filter only the walk" is new; "Directory input",
  "Ignore files in the source walk", "Precedence of ignore files" and "Deterministic order" are rewritten; task
  2.6 is rewritten and task 4.3 uses contained mode; PIN-3 keeps the codes of task 3.6. Verified with
  `openspec validate run-core-wasm-guests-from-any-language --strict` and the table "Scope after the worker host"
  (48 requirements, each with evidence or a task)
- [x] 5.2 Close the open points "Gleam relative nesting" and "Release availability" of design.html and record
  Damian Reeves's confirmation of the named-directory rule (IGN-5). Done in this update: finos/morphir-gleam#29
  (merged as `191a35e`) keeps the full path of a relative URI as the module name, with the host test
  `guest_compiles_a_relative_document_tree_without_a_root`; the release `extension/gleam/v0.4.0` has the attested
  `morphir-gleam-0.4.0.wasm` and `morphir-gleam-0.4.0.release.json`, so tasks 4.1 to 4.3 use it and keep the build
  from `191a35e` as the fallback; the scenario "Named directory that a pattern above matches" also shows a filtered
  entry below the named directory. Verified with `openspec validate run-core-wasm-guests-from-any-language
  --strict`

## Workflow follow-up

- A separate OpenSpec change makes `.morphirignore` a project-wide rule for every command that walks a project
  (the built-in compile, workspace discovery, watch, and the task graph of finos/morphir-moonbit#293 and
  finos/morphir#1121), with the library of moonrockz/moonx-tools#16 (IGN-4; design.html, "Follow-up changes").

- finos/morphir#1115 (merged) states the offer order and the host conversion for `generateModel` in
  `spec/mep/model-transport.md`; link it from the epic bead. Bead `morphir-hv6m` adds the MCK checks of the
  selection order and the conversion. The conversion is in `pkgs/morphir-host` so that the worker host and the
  browser host can call it. `host-extensions-as-workers` points to SEL-4 of this change for the `generate`
  conversion.
- Implement on the MoonBit toolchain 0.10.18 with `moonbitlang/async` 0.22.7 when that upgrade lands on main;
  add no new 0.10.17 pins.
- Archive the change after review, as `openspec/config.yaml` describes, and settle the source-selection overlap
  with `host-extensions-as-workers` at that time.
