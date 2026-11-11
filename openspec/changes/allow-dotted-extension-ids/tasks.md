# Tasks

Tracking: [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is blocked; no Beads ids are named here, and the issues are created when tracking is available. Groups are ordered by dependency, as in the design's delivery order ([REPO-1](design.html#repo-1)). Each group names its owning repository and the groups it waits for. A task marked **provisional** depends on the named open question and states the work for each outcome.

## 1. finos/morphir: the rule, its data and the shared files

Depends on: maintainer approval of this change.

- [x] 1.1 Add a normative extension id page under `docs/spec/` ([Q-PAGE](design.html#q-page), recommendation `PAGE-A`) stating the grammar, the device-name rule with the Microsoft list it follows, the rule order (`grammar`, `length`, `device-name`), exact comparison, derived names, the equality of descriptor, claims and session ids, that an id carries no trust, and the family's `$schema` URLs that carry the new grammar; verify its examples match the spec scenarios and its links resolve.
- [x] 1.2 Add the language-neutral case manifest of [CONF-1](design.html#conf-1) beside that page, each case with an input, an expected outcome and, for a refusal, the expected rule or file, covering every scenario in `specs/extensions/extension-identity/spec.md` except the state lock; verify with a data-integrity test that the manifest parses and every scenario but the state lock's is covered by at least one case.
- [x] 1.3 Read every extension id in the catalogs and bundles pinned by `.config/published-extension-bundles.toml` and record that each is valid under the new rule, and record the versions those documents are at; verify by listing the ids, versions and sources in the change's evidence.
- [ ] 1.4 Update `docs/design/draft/extensions/distribution-and-acquisition.md` so it defines, as the authority, every shared file of [DEF-1](design.html#def-1) with its path, schema URL, members, values and recursive unknown-member rule, including open nested packages and closed lock claims. This task is what lets an installer be built: until it lands, the change does not define the members of a catalog entry, a lock or the repositories file, and finos/morphir-dotnet#567 cannot be written from the change alone. The page gives a member table (name, type, required or optional, whether `null` is allowed) for each:
  - the release descriptor and the index record, `$schema` on every history line, and the history rules of [HIST-1](design.html#hist-1);
  - the installed catalog, with `extensions` as an array of entries in ascending byte order of `extensionId`;
  - the extension lock;
  - the transaction journal, its byte-array encoding and the recovery checks of [DEF-2](design.html#def-2);
  - `config/extensions/repositories.json` and `locks/extensions.repositories.lock`, and a local repository's `.publish.lock`;
  - the capability claim set, embedded without a version of its own, and standalone with its `$schema`;
  - for each JSON document, the required `$schema` member and its URL at `0.1.0-preview.1` ([VER-1](design.html#ver-1));
  - the state lock and the repositories lock with the primitive, the opening rules and the waiting rule of [DEF-3](design.html#def-3), that the two are never held together, and that a home on a network file system is not supported;
  - the spelling of `endpoint.path` and `index.identity`, and the `.stage-` temporary files that readers ignore, of [DEF-4](design.html#def-4);
  - the home root, UTF-8 without a byte order mark, I-JSON with equality by parsed value, and the reader's refusal of a catalog out of order;
  - the detection of old state before journal recovery, and one journal at a time.

  In the same page, rewrite the three places that contradict [VER-2](design.html#ver-2), not add a sentence beside them: lines 410–415 (rule 2, "Schema ranges") become the exact versions read; lines 420–431 (rules 5 and 6, the draft.1 and version-1 conversions) are removed; lines 433–444 (the release-path table and the paragraph after it) say that the host compatibility suite belonged to the Rust CLI, which is to be deleted (Decision 16), and that a current host's "host only" path is gated by the shared cases and task 5.1. State that rule 1 applies to the descriptor, the index record and the catalog. State that a reader SHALL NOT read earlier versions. Update `protocol.md` to say the MEP `extension.id` follows the same grammar when bound to a release, and that a claim set `describe` returns carries the claims `$schema` in place of `claimsVersion`; the MEP versions stay the 0.2 line. Verify the pages build in the docs job, that their examples use valid ids, that no sentence on the page still says a reader reads or converts an earlier version, and that the home-layout cases of 1.2 carry whole expected documents that the member tables produce.
- [x] 1.5 Run `mise exec -- openspec validate allow-dotted-extension-ids --strict` and `mise run openspec:verify`, and run `python -B -m unittest discover -s tests/ci` if a path filter changes; verify each passes.
- [x] 1.6 Add the old-home rule of [OLD-1](design.html#old-1) (Decision 10) and the `morphir doctor` command of [DOC-1](design.html#doc-1) to the page:
  - the trigger, detected before journal recovery;
  - the prompt, and `--yes` with the meaning the approved deployment change gives it;
  - releasing the state lock while asking, then detecting again;
  - the order of the move, the `.complete` marker and the completion of an unmarked backup;
  - the command continuing against the empty state;
  - `morphir doctor` and `morphir doctor --fix`, with output on stdout and stderr and exit codes 0, 1 and 2.

  Include the four readings confirmed as Decision 11 ([Q-OLDHOME-READINGS](design.html#q-oldhome-readings)): the refusal without a terminal or on a declined prompt, the report-only `doctor` and the prompt in `doctor --fix`. Verify the "Old home" cases of 1.2 match the page.

- [ ] 1.7 Publish a JSON Schema for each file of the extension state family under `website/static/schemas/extensions/0.1.0-preview.1/`: `release.schema.json`, `index-record.schema.json`, `catalog.schema.json`, `lock.schema.json`, `journal.schema.json`, `repositories.schema.json` and `claims.schema.json`. Each schema's `$id` is its URL under `https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/`, and each requires `$schema` with that exact value. The schemas follow the member tables of 1.4, so this task follows 1.4. Verify that every accepted case of 1.2 validates against its schema, that the documented refusals that a schema can express fail it, and that the site build serves each file at its URL.

## 2. finos/morphir-dotnet

Group 1 implementation evidence is in `docs/spec/extensions/publication-audit.md`
and its JSON inventory, the normative identity/package pages and their case
manifests, and `tools/extension-contract-data.test.ts`. Task 1.4's member tables
and task 1.7's seven schema files are implemented, with lightweight schema and
static URL mapping checks passing. Those checkboxes remain pending only for
actual Docusaurus output and schema-serving evidence from the PR's Netlify
Deploy Preview at its full head SHA. Static mapping alone does not close them.
A bounded local website build passed at `27dcc1110a9d9fc08cea1338151966174d91dea9`,
with all seven emitted schemas byte-identical to source. Current corrections need
another coordinated site verification; hosted schema availability stays pending.
No Cargo or .NET build was run. Host adoption and frozen toolchain fixture
transition remain their later groups. The existing Smithy example inventory
separates current preview claims from historical claims without changing MEP
wire/protocol versions. Journal inputs supply explicit writer bytes rather than
prescribing a serializer, and CRLF history uses distinct versions.

Depends on: 1.2 and 1.4; 2.3's old-home part and 2.6 also on 1.6.

- [ ] 2.1 Add the first-segment device-name rule and the rule order to morphir-dotnet's "An extension id is a dotted portable token" requirement and its reader; verify with the shared device-name and rule-order cases.
- [ ] 2.2 Run the shared extension id cases through the conformance runner (`src/Morphir.Conformance`); verify every case reports its expected outcome.
- [ ] 2.3 In the installer of finos/morphir-dotnet#567, write every extension into `catalog/extensions.json` and `locks/extensions/` with the family's current `$schema` URLs under the state lock, with the files, members and values that `distribution-and-acquisition.md` defines, and read only those URLs. Take both locks with `flock(LOCK_EX)` on Unix and the full-range `LockFileEx` on Windows, opened as [DEF-3](design.html#def-3) requires. On Unix, open the lock files with a direct `open` call or with `System.IO.DisableFileLocking` set, because .NET's own open takes a non-blocking `flock` (`SafeFileHandle.Unix.cs`); on Windows open with read, write and delete sharing. Call `GetFinalPathNameByHandleW` through a platform call, and check the assumptions that the base class library has no equivalent and that a mapped network drive yields a UNC path. Apply the old-home rule of [OLD-1](design.html#old-1): the prompt, `--yes`, the lock released while asking, and the move made by the same code as `morphir doctor --fix` (2.6). Verify with the version, history, journal, member-set and path cases, with a home that holds `morphir-elm` and `org.finos.morphir.fsharp-frontend`, with a test that the automatic path and `morphir doctor --fix` leave byte-identical backup trees for the same home, with a test that a second process changing the home while the prompt is open makes the host ask again, and with two-process tests: one process holds the state lock while a second process of a different build tries to install, and the second waits (its open does not fail) and writes nothing until the first releases; the same for the repositories lock and a local repository's `.publish.lock`.
- [ ] 2.4 Apply the configuration rule of [CFG-1](design.html#cfg-1) wherever the .NET host reads `[extensions.<id>]` tables; verify with the configuration cases.
- [ ] 2.5 Publish the F# frontend and backend guests' descriptors with the current release `$schema` under their dotted ids, which unblocks morphir-dotnet's task that waits on dotted descriptor ids; verify bundle authoring accepts them and their claims ids equal their descriptor ids.
- [ ] 2.6 Add `morphir doctor` to the .NET host with only what [DOC-1](design.html#doc-1) specifies: the report, `--fix`, `--yes`, the result on stdout and messages on stderr, and exit codes 0, 1 and 2. The move is the one implementation 2.3's automatic path calls. Include the report-only behavior and the prompt in `--fix` of Decision 11. Verify with the "Old home" cases and a test that a second run exits 0 and changes nothing.
- [ ] 2.7 Extend morphir-dotnet's bundle authoring so that it publishes any extension, not only morphir-dotnet's own guests: a release descriptor and index records with the family's current `$schema` URLs that current hosts read. Publish into a repository under the same repository rules as every publisher: the publish lock, the history rules of [HIST-1](design.html#hist-1) (no current line appended to a history that holds earlier lines), the checksum files beside each artifact, and the repository's own signing or authentication where it has any. This change does not design the tool itself (Decision 13). Verify with the shared history cases, and with a current descriptor for an extension that morphir-dotnet does not own that the .NET host installs.

## 3. MoonBit host

Depends on: 1.2 and 1.4.

- [ ] 3.1 Identify the repository that holds the MoonBit host's extension installation and record it in this change. This replaces the merged design's open question 6, which was a fact to find, not a decision. Verify by citing the file that parses extension ids.
- [ ] 3.2 In that repository, adopt the grammar, the rule order, the versions, the derived-name rule, the shared files of DEF-1 to DEF-4, the history rule, the configuration rule, the old-home move and `morphir doctor` of [DOC-1](design.html#doc-1), and run the shared cases; verify every case reports its expected outcome, and run the two-process state lock test of 2.3 with one process from each host.
- [ ] 3.3 Move `ecosystem/morphir-moonbit` only if 3.1 shows the host lives in that submodule; verify `git submodule status` and the MoonBit checks, or record that no pin moves.

## 4. finos/morphir: toolchain contracts

Depends on: 2.5. These tasks edit `docs/spec/toolchain/`, which is on finos/morphir#1147 and not on `main`; they land in #1147 if it is still open, or after it.

- [ ] 4.1 Carry out the three changes that `docs/spec/toolchain/index.md` lists (at `9e1f853b7`, lines 164 to 168), at whatever version the toolchain family takes under Decision 15 (its own change sets it): remove the 64-character segment limit ([Q-SEGMENT](design.html#q-segment), recommendation `SEGMENT-A`, assumed), adopt the first-segment device-name rule, and reference the extension release descriptor by its `$schema` URL at `0.1.0-preview.1` instead of `2.0.0-draft.2`. Verify with the toolchain conformance cases, a 238-character dotted identity fixture and a refused `con.example` identity.
- [ ] 4.2 Regenerate the signed repository's descriptors with the current release `$schema`, and move the TEST-ONLY signed F# fixtures from `morphir-fsharp-frontend` and `morphir-fsharp-backend` to `org.finos.morphir.fsharp-frontend` and `org.finos.morphir.fsharp-backend` by regenerating them from their labels; verify the contract task passes and no draft.2 descriptor remains in the signed repository.
- [ ] 4.3 Close the item "Dotted provider identities are decided; the descriptor change is pending" in `docs/spec/toolchain/toolset-recipe.md`, update the narrative's frontend name, and replace the list of pending changes in `index.md` with the outcome; verify the narrative test passes.

## 5. Integration

Depends on: 2.3, 2.5 and 4.2.

- [ ] 5.1 Install the dotted F# frontend from a TEST-ONLY repository with the .NET host, resolve the F# recipe that binds it, and run the readiness workflow; verify the outcome the toolchain contracts expect. Repeat with the MoonBit host once group 3 is delivered.

## 6. Republishing the existing extensions

Decided by the maintainer on 10 November 2026 (Decision 13, [Q-PUBLISHER](design.html#q-publisher)): morphir-dotnet's bundle authoring publishes every extension at the family version, and the Rust writers are not extended. Decision 16 then decided the Rust CLI is to be deleted, so its tooling writes nothing. Depends on: 1.4, 1.7 and 2.7. Does not gate groups 1 to 5.

**Provisional on [Q-PUBLISHER-READINGS](design.html#q-publisher-readings):**

1. Until 2.7 and 6.1 are delivered, a current host can install only the F# guests of 2.5, the others stay at their earlier versions, and nothing is converted.

- [ ] 6.1 With the publisher of 2.7, publish the next release of morphir-elm, morphir-python, morphir-avro, morphir-openapi and morphir-rust at the family version, from each extension's own release pipeline. Leave existing versions and their assets unchanged; they stay uninstallable by current hosts. Each first current release starts its history again, holding only current lines. Verify the .NET host installs each one from its repository.
- [ ] 6.2 Add a current-host compatibility suite that runs those current bundles through the .NET host, and later the MoonBit host, in place of the Rust CLI's suite, which goes with the Rust CLI ([REPO-1](design.html#repo-1)); verify it passes and fails on a bundle that a current host should refuse.

## No Rust work

This change plans no Rust reader or writer work and no change to the Rust CLI or `ecosystem/morphir-rust`. The Rust CLI is to be deleted from finos/morphir (maintainer, Decision 16, 10 November 2026); its exact scope is being settled separately.

## Workflow follow-up

- Follow `AGENTS.md` for review, archive, tracker closure and release approval.
- Archive the change once groups 1 to 6 are delivered, then verify the archived spec under `openspec/specs/extensions/extension-identity/`.
