# Tasks

Tracking: [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is blocked; no Beads ids are named here, and the issues are created when tracking is available. Groups are ordered by dependency, as in the design's delivery order ([REPO-1](design.html#repo-1)). Each group names its owning repository and the groups it waits for.

## 1. finos/morphir: the rule, its data and the shared files

Depends on: maintainer approval of this change.

- [ ] 1.1 Add a normative extension id page under `docs/spec/` stating the grammar, the device-name rule, exact comparison, derived names, the equality of descriptor, claims and session ids, that an id carries no trust, and the versions that carry the new grammar; verify its examples match the spec scenarios and its links resolve.
- [ ] 1.2 Add the language-neutral case manifest of [CONF-1](design.html#conf-1) beside that page, each case with an input and an expected outcome, covering every scenario in `specs/extensions/extension-identity/spec.md`; verify with a data-integrity test that the manifest parses and every scenario is covered by at least one case.
- [ ] 1.3 Read every extension id in the catalogs and bundles pinned by `.config/published-extension-bundles.toml` and record that each is valid under the new rule, and record the versions those documents are at; verify by listing the ids, versions and sources in the change's evidence.
- [ ] 1.4 Update `docs/design/draft/extensions/distribution-and-acquisition.md` so it defines, as the authority, the members and values of the release descriptor and index record at `2.0.0-draft.3`, the installed catalog at `2.0.0-draft.3`, the extension lock at `2.0.0-draft.1`, the transaction journal, the state lock and the home and repository paths, with the id grammar and the trust statement. Two installers that write equal members and values conform; their bytes need not be equal. State that a reader need not read earlier versions, and that hosts reading only earlier versions are not protected. Update `protocol.md` to say the MEP `extension.id` follows the same grammar when bound to a release. Verify the pages build in the docs job and that their examples use valid ids.
- [ ] 1.5 Run `mise exec -- openspec validate allow-dotted-extension-ids --strict` and `mise run openspec:verify`, and run `python -B -m unittest discover -s tests/ci` if a path filter changes; verify each passes.

## 2. finos/morphir-dotnet

Depends on: 1.2 and 1.4.

- [ ] 2.1 Add the first-segment device-name rule to morphir-dotnet's "An extension id is a dotted portable token" requirement and its reader; verify with the shared device-name cases.
- [ ] 2.2 Run the shared extension id cases through the conformance runner (`src/Morphir.Conformance`); verify every case reports its expected outcome.
- [ ] 2.3 In the installer of finos/morphir-dotnet#567, write every extension into `catalog/extensions.json` and `locks/extensions/` at the new drafts under the state lock, with the members and values that `distribution-and-acquisition.md` defines, and read only the new drafts; verify with the version cases and a home that holds `morphir-elm` and `org.finos.morphir.fsharp-frontend`.
- [ ] 2.4 Apply the configuration rule of [CFG-1](design.html#cfg-1) wherever the .NET host reads `[extensions.<id>]` tables; verify with the configuration cases.
- [ ] 2.5 Publish the F# frontend and backend guests' descriptors at `2.0.0-draft.3` under their dotted ids, which unblocks morphir-dotnet's task that waits on dotted descriptor ids; verify bundle authoring accepts them and their claims ids equal their descriptor ids.

## 3. MoonBit host

Depends on: 1.2 and 1.4.

- [ ] 3.1 Identify the repository that holds the MoonBit host's extension installation and record it in this change; verify by citing the file that parses extension ids.
- [ ] 3.2 In that repository, adopt the grammar, the versions, the derived-name rule and the configuration rule, and run the shared cases; verify every case reports its expected outcome.
- [ ] 3.3 Move `ecosystem/morphir-moonbit` only if 3.1 shows the host lives in that submodule; verify `git submodule status` and the MoonBit checks, or record that no pin moves.

## 4. finos/morphir: toolchain contracts

Depends on: 2.5.

- [ ] 4.1 Remove the 64-character segment limit from the toolchain contracts' provider identity grammar so it equals this rule, refining their `0.1.0-draft.1` drafts in place; verify with the toolchain conformance cases and a 238-character dotted identity fixture.
- [ ] 4.2 Move the TEST-ONLY signed F# fixtures from `morphir-fsharp-frontend` and `morphir-fsharp-backend` to `org.finos.morphir.fsharp-frontend` and `org.finos.morphir.fsharp-backend` by regenerating them from their labels; verify the contract task passes.
- [ ] 4.3 Close the "Dotted provider identities" limit in `docs/spec/toolchain/toolset-recipe.md` and update the narrative's frontend name; verify the narrative test passes.

## 5. Integration

Depends on: 2.3, 2.5 and 4.2.

- [ ] 5.1 Install the dotted F# frontend from a TEST-ONLY repository with the .NET host, resolve the F# recipe that binds it, and run the readiness workflow; verify the outcome the toolchain contracts expect. Repeat with the MoonBit host once group 3 is delivered.

## Optional later work

This work does not gate the change or any task above, and no `ecosystem/morphir-rust` pin move is planned. It would let the Rust CLI, which is legacy, read homes and repositories that current hosts write:

- finos/morphir-rust `morphir-distribution`: the dotted grammar with the device-name rule in `ExtensionId`, and the new drafts in the descriptor, index record, catalog and lock readers and writers, as `distribution-and-acquisition.md` defines them;
- finos/morphir-rust `morphir-common`: the configuration refusal of [CFG-1](design.html#cfg-1);
- the Rust CLI in this repository: quoted dotted ids in configuration diagnostics, and a dotted-id example in the `morphir extension` documentation;
- each of these would run the shared cases.

## Workflow follow-up

- Follow `AGENTS.md` for review, archive, tracker closure and release approval.
- Archive the change once groups 1 to 5 are delivered, then verify the archived spec under `openspec/specs/extensions/extension-identity/`.
