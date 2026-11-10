# Tasks

Tracking: [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is blocked; no Beads ids are named here, and the issues are created when tracking is available. Groups are ordered by dependency, as in the design's delivery order ([REPO-1](design.html#repo-1)). Each group names its owning repository and the groups it waits for. A task marked **provisional** depends on the named open question and states the work for each outcome.

## 1. finos/morphir: the rule, its data and the shared files

Depends on: maintainer approval of this change.

- [ ] 1.1 Add a normative extension id page under `docs/spec/` ([Q-PAGE](design.html#q-page), recommendation `PAGE-A`) stating the grammar, the device-name rule with the Microsoft list it follows, the rule order (`grammar`, `length`, `device-name`), exact comparison, derived names, the equality of descriptor, claims and session ids, that an id carries no trust, and the versions that carry the new grammar; verify its examples match the spec scenarios and its links resolve.
- [ ] 1.2 Add the language-neutral case manifest of [CONF-1](design.html#conf-1) beside that page, each case with an input, an expected outcome and, for a refusal, the expected rule or file, covering every scenario in `specs/extensions/extension-identity/spec.md` except the state lock; verify with a data-integrity test that the manifest parses and every scenario but the state lock's is covered by at least one case.
- [ ] 1.3 Read every extension id in the catalogs and bundles pinned by `.config/published-extension-bundles.toml` and record that each is valid under the new rule, and record the versions those documents are at; verify by listing the ids, versions and sources in the change's evidence.
- [ ] 1.4 Update `docs/design/draft/extensions/distribution-and-acquisition.md` so it defines, as the authority, every shared file of [DEF-1](design.html#def-1) with its path, version, members, values and unknown-member rule. This task is what lets an installer be built: until it lands, the change does not define the members of a catalog entry, a lock or the repositories file, and finos/morphir-dotnet#567 cannot be written from the change alone. The page gives a member table (name, type, required or optional, whether `null` is allowed) for each:
  - the release descriptor and the index record at `2.0.0-draft.3`, and the history rules of [HIST-1](design.html#hist-1);
  - the installed catalog at `2.0.0-draft.3`, with `extensions` as an array of entries in ascending byte order of `extensionId`;
  - the extension lock at `2.0.0-draft.1`;
  - the transaction journal at `2.0.0-draft.1`, its byte-array encoding and the recovery checks of [DEF-2](design.html#def-2);
  - `config/extensions/repositories.json` at `schemaVersion` 1 and `locks/extensions.repositories.lock`, and a local repository's `.publish.lock`;
  - the state lock and the repositories lock with the primitive, the opening rules and the waiting rule of [DEF-3](design.html#def-3), that the two are never held together, and that a home on a network file system is not supported;
  - the spelling of `endpoint.path` and `index.identity`, and the `.stage-` temporary files that readers ignore, of [DEF-4](design.html#def-4);
  - the home root, UTF-8 without a byte order mark, I-JSON with equality by parsed value, and the reader's refusal of a catalog out of order;
  - the detection of old state before journal recovery, and one journal at a time.

  In the same page, rewrite the three places that contradict [VER-2](design.html#ver-2), not add a sentence beside them: lines 410–415 (rule 2, "Schema ranges") become the exact versions read; lines 420–431 (rules 5 and 6, the draft.1 and version-1 conversions) are removed; lines 433–444 (the release-path table and the paragraph after it) say that the host compatibility suite is the legacy Rust CLI's gate only, and that a current host's "host only" path is gated by the shared cases and task 5.1. State that rule 1 applies to the descriptor, the index record and the catalog. State that a reader SHALL NOT read earlier versions. Update `protocol.md` to say the MEP `extension.id` follows the same grammar when bound to a release. Verify the pages build in the docs job, that their examples use valid ids, that no sentence on the page still says a reader reads or converts an earlier version, and that the home-layout cases of 1.2 carry whole expected documents that the member tables produce.
- [ ] 1.5 Run `mise exec -- openspec validate allow-dotted-extension-ids --strict` and `mise run openspec:verify`, and run `python -B -m unittest discover -s tests/ci` if a path filter changes; verify each passes.
- [ ] 1.6 **Provisional on [Q-OLDHOME](design.html#q-oldhome).** Add the old-home rule of [OLD-1](design.html#old-1) to the page: under `OLDHOME-A`, the refusal and the one command that moves old state to `backups/extensions-<time>/`; under `OLDHOME-B`, the automatic move with its stderr notice. Both define the trigger (detected before journal recovery), the order of the move, the `.complete` marker and the completion of an unmarked backup. Under `OLDHOME-C`, stop and return the question to the maintainer, because it contradicts the decision on transient formats. Verify the "Old home" cases of 1.2 match the page.

## 2. finos/morphir-dotnet

Depends on: 1.2 and 1.4; 2.3's old-home part also on 1.6.

- [ ] 2.1 Add the first-segment device-name rule and the rule order to morphir-dotnet's "An extension id is a dotted portable token" requirement and its reader; verify with the shared device-name and rule-order cases.
- [ ] 2.2 Run the shared extension id cases through the conformance runner (`src/Morphir.Conformance`); verify every case reports its expected outcome.
- [ ] 2.3 In the installer of finos/morphir-dotnet#567, write every extension into `catalog/extensions.json` and `locks/extensions/` at the new drafts under the state lock, with the files, members and values that `distribution-and-acquisition.md` defines, and read only the new drafts. Take both locks with `flock(LOCK_EX)` on Unix and the full-range `LockFileEx` on Windows, opened as [DEF-3](design.html#def-3) requires. On Unix, open the lock files with a direct `open` call or with `System.IO.DisableFileLocking` set, because .NET's own open takes a non-blocking `flock` (`SafeFileHandle.Unix.cs`); on Windows open with read, write and delete sharing. Call `GetFinalPathNameByHandleW` through a platform call, and check the assumptions that the base class library has no equivalent and that a mapped network drive yields a UNC path. Apply the old-home rule of the outcome chosen for Q-OLDHOME. Verify with the version, history, journal, member-set and path cases, with a home that holds `morphir-elm` and `org.finos.morphir.fsharp-frontend`, and with two-process tests: one process holds the state lock while a second process of a different build tries to install, and the second waits (its open does not fail) and writes nothing until the first releases; the same for the repositories lock and a local repository's `.publish.lock`.
- [ ] 2.4 Apply the configuration rule of [CFG-1](design.html#cfg-1) wherever the .NET host reads `[extensions.<id>]` tables; verify with the configuration cases.
- [ ] 2.5 Publish the F# frontend and backend guests' descriptors at `2.0.0-draft.3` under their dotted ids, which unblocks morphir-dotnet's task that waits on dotted descriptor ids; verify bundle authoring accepts them and their claims ids equal their descriptor ids.

## 3. MoonBit host

Depends on: 1.2 and 1.4.

- [ ] 3.1 Identify the repository that holds the MoonBit host's extension installation and record it in this change. This replaces the merged design's open question 6, which was a fact to find, not a decision. Verify by citing the file that parses extension ids.
- [ ] 3.2 In that repository, adopt the grammar, the rule order, the versions, the derived-name rule, the shared files of DEF-1 to DEF-4, the history rule and the configuration rule, and run the shared cases; verify every case reports its expected outcome, and run the two-process state lock test of 2.3 with one process from each host.
- [ ] 3.3 Move `ecosystem/morphir-moonbit` only if 3.1 shows the host lives in that submodule; verify `git submodule status` and the MoonBit checks, or record that no pin moves.

## 4. finos/morphir: toolchain contracts

Depends on: 2.5. These tasks edit `docs/spec/toolchain/`, which is on finos/morphir#1147 and not on `main`; they land in #1147 if it is still open, or after it.

- [ ] 4.1 Carry out the three changes that `docs/spec/toolchain/index.md` lists (at `9e1f853b7`, lines 164 to 168), refining `0.1.0-draft.1` in place after confirming that no toolchain reader has been released: remove the 64-character segment limit ([Q-SEGMENT](design.html#q-segment), recommendation `SEGMENT-A`, assumed), adopt the first-segment device-name rule, and move the referenced extension release descriptor from `2.0.0-draft.2` to `2.0.0-draft.3`. The page already says a reader reads "each one only at the version listed"; no wording change is left there. Verify with the toolchain conformance cases, a 238-character dotted identity fixture and a refused `con.example` identity.
- [ ] 4.2 Regenerate the signed repository's descriptors at `2.0.0-draft.3`, and move the TEST-ONLY signed F# fixtures from `morphir-fsharp-frontend` and `morphir-fsharp-backend` to `org.finos.morphir.fsharp-frontend` and `org.finos.morphir.fsharp-backend` by regenerating them from their labels; verify the contract task passes and no draft.2 descriptor remains in the signed repository.
- [ ] 4.3 Close the item "Dotted provider identities are decided; the descriptor change is pending" in `docs/spec/toolchain/toolset-recipe.md`, update the narrative's frontend name, and replace the list of pending changes in `index.md` with the outcome; verify the narrative test passes.

## 5. Integration

Depends on: 2.3, 2.5 and 4.2.

- [ ] 5.1 Install the dotted F# frontend from a TEST-ONLY repository with the .NET host, resolve the F# recipe that binds it, and run the readiness workflow; verify the outcome the toolchain contracts expect. Repeat with the MoonBit host once group 3 is delivered.

## 6. Republishing the existing extensions

**Provisional on [Q-PUBLISHER](design.html#q-publisher).** Depends on: 1.4. Does not gate groups 1 to 5.

- [ ] 6.1 Under `PUBLISHER-A`: in finos/morphir-rust `morphir-distribution`, make the descriptor and index record writers write `2.0.0-draft.3` with the dotted grammar and the history rule of [HIST-1](design.html#hist-1), and let the first draft.3 release of an extension start its history again, holding only draft.3 lines; the Rust readers stay out of scope. Under `PUBLISHER-B`: add the same publishing to morphir-dotnet's bundle authoring for releases it does not own. Under `PUBLISHER-C`: record that current hosts install only the F# guests, and do nothing else. Verify, under A or B, with the shared history cases.
- [ ] 6.2 Under `PUBLISHER-A` or `PUBLISHER-B`: publish the next release of morphir-elm, morphir-python, morphir-avro, morphir-openapi and morphir-rust at draft.3, leaving existing versions and their assets unchanged (they stay uninstallable by current hosts), and add a current-host compatibility suite that runs those draft.3 bundles through the .NET host; verify the .NET host installs each one.

## Optional later work

This work does not gate the change or any task above, and no `ecosystem/morphir-rust` pin move is planned for it. It would let the Rust CLI, which is legacy, read homes and repositories that current hosts write:

- finos/morphir-rust `morphir-distribution`: the dotted grammar with the device-name rule in `ExtensionId`, and the new drafts, the journal version and the path spelling in the descriptor, index record, catalog, lock and journal readers, as `distribution-and-acquisition.md` defines them;
- finos/morphir-rust `morphir-common`: the configuration refusal of [CFG-1](design.html#cfg-1);
- the Rust CLI in this repository: quoted dotted ids in configuration diagnostics, and a dotted-id example in the `morphir extension` documentation;
- each of these would run the shared cases.

## Workflow follow-up

- Follow `AGENTS.md` for review, archive, tracker closure and release approval.
- Archive the change once groups 1 to 5 are delivered and group 6 is delivered or closed under `PUBLISHER-C`, then verify the archived spec under `openspec/specs/extensions/extension-identity/`.
