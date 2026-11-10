# Tasks

Tracking: [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is not used for this proposal; no Beads ids are named here, and the issues are created when tracking is available. Groups follow the design's delivery order ([REPO-1](design.html#repo-1)). Each group names its owning repository and what it waits for. A task marked **provisional** depends on the named open question.

## 1. finos/morphir: the rule, its data and the shared files

Depends on: maintainer approval of this change, and the approval of finos/morphir#1149 (merged as a proposal at `9690dfc37`).

- [ ] 1.1 Record which outcome of [VER-1](design.html#ver-1) applies: `PKGVER-A` if no descriptor, index record, catalog or lock has been published at #1149's drafts when this change is approved, `PKGVER-B` otherwise. Replace "the package drafts" in this change's spec with the chosen version strings. Under `PKGVER-A`, also amend #1149's sentence that `2.0.0-draft.3` "differs from `2.0.0-draft.2` only in the id grammar". Verify by citing the published documents checked, or their absence.
- [ ] 1.2 In `docs/design/draft/extensions/distribution-and-acquisition.md`, as part of or after #1149's task 1.4, define the `package` member (`format`, `root`, `entryPoint`, `executables`, `treeSha256`) in the release descriptor, the index record, the installed catalog entry and the extension lock at the package drafts. Give the package store layout of [STORE-1](design.html#store-1), and replace the page's `.tgz` process example with a package. If #1149's review fixes (`7f22dfea2`) are not merged, state the lease's lock calls in full. Verify the page builds in the docs job and its examples validate against the spec's rules.
- [ ] 1.3 Add a normative package page under `docs/spec/` with the manifest format, the refusal codes in their order, the collision keys with Unicode 17.0.0, the bounds, modes, store, launch, lease, collection and trust rules; verify its examples match the spec scenarios and its links resolve.
- [ ] 1.4 Add the case data of [CONF-1](design.html#conf-1) beside that page: a deterministic generator script under `tools/` (TypeScript run by Bun) that writes each archive's bytes, the checked-in archives, and a JSON manifest of cases with the expected outcome, code and entry path. Verify with a data-integrity test that regenerating changes no byte, that every refusal code but `install_path_too_long` has a case, and that every spec scenario is covered by a case or named as a host test.
- [ ] 1.5 Run `mise exec -- openspec validate add-extension-packages --strict` and `mise run openspec:verify`, and `python -B -m unittest discover -s tests/ci` if a path filter changes; verify each passes.

## 2. finos/morphir-dotnet

Depends on: 1.2, 1.3 and 1.4.

- [ ] 2.1 List the F# frontend's self-contained publish output for each first-delivery platform: file count, total size, longest tree path in UTF-16 code units, any symbolic link or non-ASCII name, and which files carry an executable bit. Record it in this change. Verify the counts against the publish directory of `SelfContainedProcess.pubxml`, and confirm or correct the design's assumption of about 239 files and 121 MB.
- [ ] 2.2 In the installer of finos/morphir-dotnet#567, install packages: the archive checks, entry rules and order of [EXT-1](design.html#ext-1), the bounds of [EXT-2](design.html#ext-2), the modes of [MODE-1](design.html#mode-1), staging and publication of [STORE-1](design.html#store-1), and the lock and catalog `package` member. Replace the installer plan's ASCII rule (ARC-1) for package entries, and its "target archive holds exactly one executable" rule (Q-ARCHIVE). Check that .NET's ZIP and tar readers expose local header names, entry types and PAX records, or read those structures directly. **Provisional on [Q-VERIFY](design.html#q-verify):** the activation check of the chosen outcome. Verify with every shared case.
- [ ] 2.3 Prove the operating-system rules with tests on Windows, Linux and macOS: a directory rename within one volume is atomic and fails when the target exists; two sessions share a lease; collection skips a leased package and removes an unleased, unreferenced one; an abandoned `.stage-` directory is removed only when its `owner` lock is free. Verify the tests pass on each platform.
- [ ] 2.4 Measure on the first-delivery platforms, for the F# frontend package: install time, the activation structure check, a full rehash and a private copy. Record the numbers in this change. **Provisional on [Q-VERIFY](design.html#q-verify):** if a full rehash costs less than the design estimates, report that to the maintainer before the question is answered. Verify the numbers come from at least three runs on each platform.
- [ ] 2.5 Check the launch assumptions:
  - on Windows, the longest store path that `CreateProcessW` and the frontend's runtime accept without long-path support, which settles `package.install_path_too_long`;
  - on macOS, that an entry point written by the host carries no quarantine attribute and starts without a Gatekeeper prompt.

  Verify with a test that installs a package at a path one unit under and one unit over the limit.
- [ ] 2.6 Publish the F# frontend as a package for each platform, with its `treeSha256`, from the installer plan's adoption task 3.3, and install it with the Native AOT host from a TEST-ONLY repository; verify that the readiness workflow passes with the installed frontend.

## 3. MoonBit host

Depends on: 1.3 and 1.4.

- [ ] 3.1 In the repository that holds the MoonBit host's extension installation (located by finos/morphir#1149's task 3.1), refuse package artifacts with `package.unsupported` until 3.2 is delivered; verify with the single-file and `package.unsupported` cases.
- [ ] 3.2 Adopt the package rules, shipping Unicode 17.0.0 normalization, case-folding and uppercase data, and run the shared cases and the operating-system tests of 2.3; verify every case reports its expected outcome.

## 4. finos/morphir: toolchain contracts

Depends on: 2.6. These pages are in `docs/spec/toolchain/`, on finos/morphir#1147 and not on `main`; the tasks land in #1147 if it is still open, or after it.

- [ ] 4.1 Close question M2 in `docs/spec/toolchain/toolset-recipe.md` with this change's package form. Make final the rule that a process provider's `artifactTarget` is one archive per platform. State that `artifactSha256` is the archive digest and that the tree digest comes from the bound descriptor, so the portable lock needs no new member. Add the consistency check that a package's `format` matches the target suffix. Verify with a recipe case for each.
- [ ] 4.2 In `docs/spec/toolchain/installation-receipt.md`, say that a package's `launch.program` names the entry point in the published tree, and how extension collection treats a package a receipt names; verify with a receipt case.
- [ ] 4.3 Regenerate the TEST-ONLY signed F# frontend fixtures as packages with a `treeSha256`; verify the contract task passes.

## Optional later work

This work does not gate the change or any task above, and no `ecosystem/morphir-rust` pin move is planned for it:

- finos/morphir-rust `morphir-distribution`: reuse the tool extractor for extension packages with this change's rules (in particular the executable set from the descriptor, the bounds and the Unicode 17.0.0 data), and stop refusing archives that carry a `package` member at publication;
- the Rust CLI: install and start packages;
- each would run the shared cases.

## Workflow follow-up

- Follow `AGENTS.md` for review, archive, tracker closure and release approval.
- Archive the change once groups 1 to 4 are delivered, then verify the archived spec under `openspec/specs/extensions/extension-packages/`.
