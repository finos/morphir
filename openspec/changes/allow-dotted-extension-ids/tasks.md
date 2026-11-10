# Tasks

Tracking: [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is blocked; no Beads ids are named here, and the issues are created when tracking is available. Groups are ordered by dependency, as in the design's delivery order ([REPO-1](design.html#repo-1)). Each group names its owning repository and the groups it waits for.

## 1. finos/morphir: the rule and its data

Depends on: maintainer approval of this change.

- [ ] 1.1 Add a normative extension id page under `docs/spec/` stating the grammar, the device-name rule, exact comparison, derived names, the equality of descriptor, claims and session ids, that an id carries no trust, and the versions that carry a dotted id; verify its examples match the spec scenarios and its links resolve.
- [ ] 1.2 Add the language-neutral case manifest of [CONF-1](design.html#conf-1) beside that page, each case with an input and an expected outcome, covering every scenario in `specs/extensions/extension-identity/spec.md`; verify with a data-integrity test that the manifest parses and every scenario is covered by at least one case.
- [ ] 1.3 Read every extension id in the catalogs and bundles pinned by `.config/published-extension-bundles.toml` and record that each is valid under the new rule; verify by listing the ids and their sources in the change's evidence.
- [ ] 1.4 Update `docs/design/draft/extensions/distribution-and-acquisition.md`: the descriptor id grammar, `2.0.0-draft.3` and its writer rule, the lock's `2.0.0-draft.1`, and the trust statement. Update `protocol.md` to say the MEP `extension.id` follows the same grammar when bound to a release. Verify the pages build in the docs job and their examples use valid ids.
- [ ] 1.5 Run `mise exec -- openspec validate allow-dotted-extension-ids --strict` and `mise run openspec:verify`, and run `python -B -m unittest discover -s tests/ci` if a path filter changes; verify each passes.

## 2. finos/morphir-rust: morphir-distribution and configuration

Depends on: 1.1 and 1.2.

- [ ] 2.1 Change `ExtensionId` to the dotted grammar with the 238-character limit and the first-segment device-name rule, keeping its file name check; verify with unit tests that read the shared case manifest's grammar, device-name and length cases.
- [ ] 2.2 Add `2.0.0-draft.3` to the descriptor, index record and catalog readers and writers, written only for dotted ids, and the extension lock's `2.0.0-draft.1`; verify that single-segment documents are written byte-identical to the current output, that every earlier version still reads, and that a dotted id at draft.2 or in a `1.0` lock is refused.
- [ ] 2.3 Verify that derived names (repository history, lock, journal, catalog key) work for dotted ids by publishing, installing, activating and removing a dotted-id test extension, and by running the derived-name cases, including on Windows.
- [ ] 2.4 Refuse an `extensions` configuration entry that nests tables in place of extension settings, with the quoted spelling in the message, and print dotted configuration keys quoted; verify with the configuration cases.
- [ ] 2.5 Document the rule in the crate's public docs and changelog and release the crates; verify the release notes name the new drafts and that the host compatibility tests pass.

## 3. finos/morphir: Rust CLI and the morphir-rust pin

Depends on: 2.5.

- [ ] 3.1 Move the `ecosystem/morphir-rust` pin to the release from 2.5 in the same pull request as the CLI changes. This change is the proposal that covers that pin move. Verify `git submodule status` shows the release commit and that the host compatibility suite passes every bundle in `.config/published-extension-bundles.toml` unchanged.
- [ ] 3.2 Quote dotted ids in the CLI's configuration diagnostics, for example `[extensions."org.finos.morphir.fsharp-frontend"].command`; verify with a CLI test.
- [ ] 3.3 Add an end-to-end CLI test that authors, publishes, installs and runs a dotted-id test extension, and checks that an earlier draft reader refuses its descriptor by version; verify it passes in CI.
- [ ] 3.4 Update the CLI documentation for `morphir extension` commands and the configuration reference with a dotted-id example; verify `mise run docs:cli` is unchanged or regenerated and the docs job passes.

## 4. MoonBit host

Depends on: 1.2.

- [ ] 4.1 Identify the repository that holds the MoonBit host's extension installation and record it in this change; verify by citing the file that parses extension ids.
- [ ] 4.2 In that repository, adopt the grammar, the versions and the derived-name rule, and run the shared cases; verify every case reports its expected outcome.
- [ ] 4.3 Move `ecosystem/morphir-moonbit` only if 4.1 shows the host lives in that submodule; verify `git submodule status` and the MoonBit checks, or record that no pin moves.

## 5. finos/morphir-dotnet

Depends on: 1.2.

- [ ] 5.1 Add the first-segment device-name rule to morphir-dotnet's "An extension id is a dotted portable token" requirement and its reader; verify with the shared device-name cases.
- [ ] 5.2 Run the shared extension id cases through the conformance runner (`src/Morphir.Conformance`); verify every case reports its expected outcome.
- [ ] 5.3 Publish the F# frontend and backend guests' descriptors at `2.0.0-draft.3` under their dotted ids, which unblocks morphir-dotnet's task that waits on dotted descriptor ids; verify bundle authoring accepts them and their claims ids equal their descriptor ids.

## 6. finos/morphir: toolchain contracts

Depends on: 3.1 and 5.3.

- [ ] 6.1 Remove the 64-character segment limit from the toolchain contracts' provider identity grammar so it equals this rule, refining their `0.1.0-draft.1` drafts in place; verify with the toolchain conformance cases and a 238-character dotted identity fixture.
- [ ] 6.2 Move the TEST-ONLY signed F# fixtures from `morphir-fsharp-frontend` and `morphir-fsharp-backend` to `org.finos.morphir.fsharp-frontend` and `org.finos.morphir.fsharp-backend` by regenerating them from their labels; verify the contract task passes.
- [ ] 6.3 Close the "Dotted provider identities" open question in `docs/spec/toolchain/toolset-recipe.md` and update the narrative's frontend name; verify the narrative test passes.

## 7. Integration

Depends on: 3.3, 4.2, 5.2 and 6.2.

- [ ] 7.1 Install the dotted F# frontend from a TEST-ONLY repository with the Rust host and the .NET host, resolve the F# recipe that binds it, and run the readiness workflow; verify both hosts reach the same outcome.

## Workflow follow-up

- Follow `AGENTS.md` for review, archive, tracker closure and release approval.
- Archive the change once every group is delivered, then verify the archived spec under `openspec/specs/extensions/extension-identity/`.
