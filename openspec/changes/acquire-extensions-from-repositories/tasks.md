# Tasks

## 1. Acquisition core in MoonBit with local repositories (morphir-ukvn.5.64.34.1)

- [ ] 1.1 Create the acquisition package (DIST-1) with host edges for HTTP GET, storage, clock and prompt, a worker
  host interface for probe and activation (HOST-1), and in-memory edges and an in-memory worker for tests; verify it
  builds on native, js, wasm and wasm-gc with no new warnings
- [ ] 1.2 Read release descriptor `2.0.0-draft.2` and claims `0.1.0-draft.2`, including the draft.1 conversion and
  must-ignore-unless-critical rules (DIST-3); verify with fixtures copied from the finos/morphir-python
  `extension/python/v0.4.1` and finos/morphir-elm `extension/elm/v0.4.1` releases (the latter is the Elm classic
  extension under its old name), plus refusal fixtures
- [ ] 1.3 Define `morphir-extension-index` `0.1.0-draft.1` (`index.json` and per-extension JSON Lines) with a JSON
  Schema and examples (DIST-3), with the digest of each history in `index.json`; verify the schema validates the
  examples and rejects an artifact without a digest and a root without a history digest
- [ ] 1.4 Implement the `extensions/v1` layout with staged writes, the content-addressed store, catalog and locks
  (DIST-2); verify the "Versioned home layout" and "Lock records the selection" scenarios of `extensions/installation`
  as tests, including a home that holds Rust CLI state
- [ ] 1.5 Implement local-directory repositories in the new index format: `repository init`, `repository publish` of
  a staged bundle, resolution by channel and exact version, digest checks, update and uninstall, with probes through
  the in-memory worker; verify the "Install in one command", "Check the digest before storing", "Probe the claims",
  "Update and uninstall" and "Local-directory repositories" scenarios as tests
- [ ] 1.6 Connect probe and offline activation to the worker host once it lands (catalog and lock agree, rehash,
  handshake against recorded claims); verify the "Probe the claims" scenario with a real guest and the "Offline
  activation" scenario with a tampered stored artifact
- [ ] 1.7 Switch `extension bundle|repository|install|update|uninstall|list|search` in `apps/morphir` to the package,
  with `bundle` producing the staged bundle that `publish --stage` will reuse, and remove `--services-pin` and
  `--services-helper` from them; verify the "No helper flags" scenario and port
  `scripts/test-local-extension-lifecycle.ts` to run without the helper
- [ ] 1.8 Update `apps/morphir/docs/extension.md` ("Controlled local repositories") for the new commands, layout and
  index format; verify the documented commands run as written in a fresh `MORPHIR_HOME`

## 2. GitHub-hosted repositories and capability lookup (morphir-ukvn.5.64.34.2)

- [ ] 2.1 Read GitHub-hosted repositories from `github:<owner>/<repo>[@<branch>][/<path>]` through
  `raw.githubusercontent.com` (REPO-1), with the native HTTP edge and a fetch edge for js; verify against a local HTTP
  fixture server and one live read of a test repository
- [ ] 2.2 Add `extension repository add <name> github:...` with the index check, and ship `finos` as the default
  enabled repository; verify the "Default finos repository", "Add a GitHub-hosted repository in one command" and "No
  trust step" scenarios
- [ ] 2.3 Cache accepted indexes, record serials, refuse rollbacks and use cached indexes offline (REPO-2); verify the
  "Index freshness" and "Cached indexes and offline use" scenarios, and refuse a history that does not match the root;
  verify the "History that does not match the root" scenario
- [ ] 2.4 Implement search by name and the capability query (REPO-3); verify the "Search by name and by capability"
  scenarios, including the platform mismatch and the "Hosts that cannot start processes" filter
- [ ] 2.5 Document GitHub-hosted repositories in `apps/morphir/docs/extension.md`; verify the docs build and the
  examples validate against the index schema

## 3. Publishing and repository admission (morphir-ukvn.5.64.34.4)

- [ ] 3.1 Add `morphir extension publish --stage <dir>` over prebuilt artifacts and an optional `release.json`, and
  `--release <dir>` (GitHub release with bundle and `.sigstore.json` files), failing outside GitHub Actions without an
  OIDC token (PUB-1); verify the "Publish in a release workflow" scenarios in a test repository
- [ ] 3.2 Add `morphir extension publish setup` that writes the release workflow (single job for WASM, platform matrix
  plus one release job for native) and prints the publisher identity; verify both generated forms pass `actionlint`
  and publish a test release
- [ ] 3.3 Add `morphir repository setup` (index branch, empty index, publishers file, admission workflow, printed
  protection settings when the token lacks admin rights) and `morphir repository publisher add` (PUB-2); verify the
  "Repository creation" and "Registered publishers" scenarios in a test repository
- [ ] 3.4 Add `morphir repository admit` (find releases of registered publisher repositories, check digests and claims
  with the user-side code, append records, record history digests, raise the serial, attest `index.json`, push, heartbeat); verify the
  "Admission by the owner's workflow" scenarios, including an unregistered publisher repository
- [ ] 3.5 Add optional mirroring of admitted artifacts to Pages with the location recorded in the entry; verify the
  "Mirrored artifacts for the browser" scenario and a cross-origin read of a mirrored artifact
- [ ] 3.6 Publish the MoonBit frontend extension (`apps/morphir-extension`) from this repository through the generated
  workflow, and open the finos/morphir pull request that creates the `finos` index and registers the Elm, Gleam,
  MoonBit and Python publishers; verify `morphir extension search` lists the MoonBit frontend from `finos` in a fresh
  home
- [ ] 3.7 Measure the default publisher and owner paths against "Short default setup"; verify each takes at most
  three commands in a fresh test repository and record the transcript in the pull request
- [ ] 3.8 Write the publisher and owner guides; verify each guide's commands run as written in a test repository

## 4. Provider acquisition in compile and generate (morphir-ukvn.5.64.34.5)

- [ ] 4.1 Build the compile and generate provider list from the installed catalog with `--provider` and the workspace
  provider setting (PROV-1), closing `morphir-ukvn.5.64.30`; verify the "Installed providers are used" scenarios
- [ ] 4.2 Map an installed frontend's result into the checkpoint backend so compile keeps its options, formats and
  report (PROV-2); verify the "Same compile contract for installed providers" scenario against the built-in Elm and
  MoonBit frontends on the existing compile fixtures
- [ ] 4.3 On a miss, run the capability query, offer the match and install it in interactive runs; verify the
  "On-demand acquisition" scenarios with a local fixture repository
- [ ] 4.4 Add `--install-missing` and the not-found error; verify the "Unattended acquisition" and "Nothing found"
  scenarios
- [ ] 4.5 Document on-demand installation in the CLI README; verify the documented commands run as written

## 5. morphir setup (morphir-ukvn.5.64.34.6)

- [ ] 5.1 Add `morphir setup` with the recommended-set screen, including providers the workspace configuration needs
  (UX-1); verify the "Recommended set first" scenarios with interactive-input tests
- [ ] 5.2 Add the customize screen grouped by role and language or target with a provider choice per row; verify the
  "Customize by capability" scenario
- [ ] 5.3 Add the review screen, the unattended options and rerun behavior; verify the "Review before install",
  "Unattended setup" and "Safe to rerun" scenarios
- [ ] 5.4 Document `morphir setup` and its difference from `morphir toolchain setup`; verify the documented commands
  run as written

## 6. Remove the built-in Elm and MoonBit frontends (morphir-ukvn.5.64.34.7)

- [ ] 6.1 Confirm the `finos` index serves the Elm frontend extension from finos/morphir-elm (`morphir-elm` 0.5.0 or
  later, the portable WASM guest, which needs no per-platform build) and the MoonBit frontend extension from this
  repository for every platform the CLI releases for, and that the group 4 and 5 acceptance
  passes with them; verify by installing both from `finos` in a fresh home
- [ ] 6.2 Remove `@elm_frontend` and `@moonbit_frontend` from `apps/morphir/moon.pkg` and their built-in
  registration; verify the "Frontends are not built in" scenario, that the existing compile tests pass unchanged, and
  record CLI build time and binary size before and after in the pull request
- [ ] 6.3 Update the user documentation for first use (`morphir setup` or on-demand install) and the breaking-change
  notes; verify the docs build and link check pass

## Workflow follow-up

- Archive the change after the last group's pull request merges, following "Land a change" in CONTRIBUTING.md.
