# Tasks

Tracking: [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is not used for this proposal; no Beads ids are named here, and the issues are created when tracking is available. Groups follow the design's delivery order ([REPO-1](design.html#repo-1)). Each group names its owning repository and what it waits for. A task marked **provisional** depends on the named open question.

## 1. finos/morphir: the rule, its data and the shared files

Depends on: maintainer approval of this change, and the approval of finos/morphir#1149 (merged as a proposal at `9690dfc37`).

- [ ] 1.1 Record which outcome of [VER-1](design.html#ver-1) applies. `PKGVER-A` applies if, when this change is approved, the extension state family's `0.1.0-preview.1` schemas are not yet published under `website/static/schemas/extensions/0.1.0-preview.1/` on `main`, and no released host, publisher or tool reads or writes `0.1.0-preview.1`; otherwise `PKGVER-B`. "Released" means a tagged release, a published package or a release asset. Check at least:
  - the schema directory on `main`, and whether #1150's task 1.7 has been delivered;
  - the releases and tags of finos/morphir, finos/morphir-dotnet (and the `Morphir.Tool` NuGet package), finos/morphir-rust and the MoonBit host's repository;
  - the release assets of every repository named in `.config/published-extension-bundles.toml`;
  - any extension repository the morphir-dotnet documentation names.

  Replace "the package version" in this change's spec with the chosen version, `0.1.0-preview.1` or `0.1.0-preview.2`, and under `PKGVER-B` change the examples that show `0.1.0-preview.1`, such as the tree manifest header. Under `PKGVER-A`, also add the `package` member to #1149's definition of `0.1.0-preview.1`, so that #1150's task 1.7 publishes it in the first schemas. Verify by listing each place checked and what it held.
- [ ] 1.2 In `docs/design/draft/extensions/distribution-and-acquisition.md`, as part of or after #1149's task 1.4:
  - define the `package` member (`format`, `root`, `entryPoint`, `executables`, `treeSha256`) in the release descriptor, the index record, the installed catalog entry and the extension lock at the package version, with the rule that `artifacts.package` or `extensions.package` is listed in `critical`, and with the family's `$schema` URLs in every example;
  - give the package store layout of [STORE-1](design.html#store-1), with the owner and lease files beside their directories;
  - replace the page's `.tgz` process example with a package, and state the refusal of an archive-named single-file artifact;
  - if #1150 is not merged, state the lock calls and opening rules in full.

  Verify the page builds in the docs job and its examples validate against the spec's rules.
- [ ] 1.3 Add a normative package page under `docs/spec/` with:
  - the reading rules of [RD-1](design.html#rd-1) for each format;
  - the ASCII name rule and the ASCII case-collision rule;
  - the manifest format and the refusal codes in their order;
  - the bounds, read-only modes, store, publication and recording, launch, lease, collection and trust rules.

  Verify its examples match the spec scenarios and its links resolve.
- [ ] 1.4 Add the case data of [CONF-1](design.html#conf-1) beside that page. It comprises a deterministic generator script under `tools/` (TypeScript run by Bun) that writes each archive's bytes, the checked-in archives, and a JSON manifest of cases with the expected outcome, code and entry name. The `archive_too_large` case states a length without bytes. Verify with a data-integrity test that regenerating changes no byte, that every refusal code except `install_path_too_long`, `publish_busy` and `store_not_one_volume` has a case, and that every spec scenario is covered by a case or named as a host test.
- [ ] 1.5 Publish the `package` member in the family's JSON Schemas ([VER-1](design.html#ver-1)), following the member definitions of 1.2:
  - under `PKGVER-A`, add it to `release.schema.json`, `index-record.schema.json`, `catalog.schema.json` and `lock.schema.json` under `website/static/schemas/extensions/0.1.0-preview.1/` as part of #1150's task 1.7, before those schemas are first published;
  - under `PKGVER-B`, publish all seven schemas of the family again under `website/static/schemas/extensions/0.1.0-preview.2/`, each with its `$id` under `https://morphir.finos.org/schemas/extensions/0.1.0-preview.2/` and requiring that exact `$schema`, the four above with `package`; leave the `0.1.0-preview.1/` files unchanged.

  A schema states the `package` members and their types; the rules a schema cannot express, such as `critical` listing `artifacts.package`, stay in the page and the cases. Verify that every valid descriptor, catalog and lock of 1.4's cases validates against its schema, and that the site build serves each file at its URL.
- [ ] 1.6 Run `mise exec -- openspec validate add-extension-packages --strict` and `mise run openspec:verify`, and `python -B -m unittest discover -s tests/ci` if a path filter changes; verify each passes.

## 2. finos/morphir-dotnet

Depends on: 1.2, 1.3, 1.4 and 1.5.

- [ ] 2.1 List the F# frontend's self-contained publish output for each first-delivery platform: file count, total size, longest tree path, any symbolic link or non-ASCII name, and which files carry an executable bit. Record it in this change. Verify the counts against the publish directory of `SelfContainedProcess.pubxml`, confirming or correcting the design's assumptions: about 239 files and 121 MB, a longest path near 70 units, and only ASCII names.
- [ ] 2.2 In the installer of finos/morphir-dotnet#567, install packages:
  - the descriptor rules of [PKG-1](design.html#pkg-1), including `critical`;
  - the reading rules of [RD-1](design.html#rd-1);
  - the entry rules and order of [EXT-1](design.html#ext-1) and the bounds of [EXT-2](design.html#ext-2);
  - the read-only modes of [MODE-1](design.html#mode-1);
  - staging, publication and recording of [STORE-1](design.html#store-1) in one state-lock scope;
  - the lock and catalog `package` member.

  Keep the installer plan's ASCII name rule (ARC-1), and replace its "target archive holds exactly one executable" rule (Q-ARCHIVE). Decode ZIP external attributes and check local headers against the central directory, through `ZipArchive` or by reading those structures directly; read tar entry types and pax records the same way. **Provisional on [Q-VERIFY](design.html#q-verify):** the activation check of the chosen outcome. Verify with every shared case.
- [ ] 2.3 Prove the operating-system rules with tests on Windows, Linux and macOS:
  - a no-replace rename publishes and fails when the target exists;
  - a rename across volumes fails with `package.store_not_one_volume`;
  - record whether a Windows directory rename fails while a file inside it is open (knowledge-base Q130589), and show the publication works either way;
  - an abandoned staging directory is removed only when its owner lock is free, and a host's fresh staging directory is never removed;
  - collection cannot fall between publication and recording;
  - two sessions share a lease;
  - on Unix, a guest that outlives a killed host keeps the inherited lease, so collection keeps the package;
  - on Windows, killing the host ends every process in the guest's job;
  - at the end of a session the host ends a guest's leftover child before it releases the lease.

  Check that .NET can start a child in a new process group with one inherited descriptor, and inside a job object, through platform calls. Verify the tests pass on each platform.
- [ ] 2.4 Measure on the first-delivery platforms, for the F# frontend package: install time, the activation structure check, a full rehash and a private copy. Record the numbers in this change. **Provisional on [Q-VERIFY](design.html#q-verify):** if a full rehash costs less than the design estimates, report that to the maintainer before the question is answered. Verify the numbers come from at least three runs on each platform.
- [ ] 2.5 Check the launch assumptions:
  - on Windows, that `CreateProcessW` and the frontend's runtime accept store paths up to 259 UTF-16 code units, and directories up to 247, without long-path support;
  - on macOS, that an entry point written by the host carries no quarantine attribute and starts without a Gatekeeper prompt.

  Verify with a test that installs a package at a path one unit under and one unit over each limit.
- [ ] 2.6 Publish the F# frontend as a package for each platform, with its `treeSha256` and `artifacts.package` in `critical`, from the installer plan's adoption task 3.3, and install it with the Native AOT host from a TEST-ONLY repository; verify that the readiness workflow passes with the installed frontend. **Depends on [Q-LAUNCH](design.html#q-launch)** for how it is started.
- [ ] 2.7 Make the publisher of #1150's task 2.7, morphir-dotnet's bundle authoring (Decision 13), write package artifacts. It computes `treeSha256` by [TREE-1](design.html#tree-1) from the archive it publishes, writes the `package` member, lists `artifacts.package` in `critical`, and refuses to publish an archive that a host would refuse under [RD-1](design.html#rd-1) and [EXT-1](design.html#ext-1). It also publishes the existing single-executable `.tgz` extensions, such as morphir-elm, as one-file packages when they are next released. Verify with the valid package cases, whose published descriptors must match the expected `package` members, and with one refusal case per rule group.

## 3. MoonBit host

Depends on: 1.3 and 1.4.

- [ ] 3.1 In the repository that holds the MoonBit host's extension installation (located by finos/morphir#1149's task 3.1), refuse package artifacts with `package.unsupported` until 3.2 is delivered. Also refuse a document that lists `artifacts.package` in `critical` if the host does not read the package version. Verify with the single-file, `package.unsupported` and critical cases.
- [ ] 3.2 Adopt the package rules and run the shared cases and the operating-system tests of 2.3; verify every case reports its expected outcome.

## 4. finos/morphir: toolchain contracts

Depends on: 2.6. These pages are in `docs/spec/toolchain/`, on `origin/feat/morphirup-deployment-acquisition` (finos/morphir#1147) and not on `main`. The tasks land there if it is still open, or after it.

- [ ] 4.1 In `docs/spec/toolchain/toolset-recipe.md`, make final the item "A multi-file extension is a package form that a separate change defines", which at `9e1f853b7` keeps the binding of the Native AOT offering's process frontend, "one archive per platform in `artifactTarget`", provisional:
  - say that a process provider's `artifactTarget` is the artifact's file, the archive for a package and the executable for a single-file artifact;
  - say that `artifactSha256` is that file's digest and that a package's tree digest comes from the bound descriptor, so the portable lock needs no new member;
  - add the consistency checks that a package's `format` matches the target's suffix and that its descriptor lists `artifacts.package` in `critical`.

  Verify with a recipe case for each.
- [ ] 4.2 In `docs/spec/toolchain/installation-receipt.md`, say that a package's `launch.program` names the entry point in the published tree, and how a receipt names the package, so that extension collection can stop keeping every package in a home with a receipt; verify with a receipt case.
- [ ] 4.3 Regenerate the TEST-ONLY signed F# frontend fixtures as packages with a `treeSha256`; verify the contract task passes.

## No Rust work

The maintainer decided on 10 November 2026 that the Rust CLI is to be deleted from finos/morphir (Decision 16). This change plans no Rust reader, installer or writer, and no `ecosystem/morphir-rust` pin move.

## Workflow follow-up

- Follow `AGENTS.md` for review, archive, tracker closure and release approval.
- Archive the change once groups 1 to 4 are delivered, then verify the archived spec under `openspec/specs/extensions/extension-packages/`.
