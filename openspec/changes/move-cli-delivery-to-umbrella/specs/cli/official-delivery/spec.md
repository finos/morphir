# Spec Delta

## Purpose

Defines how finos/morphir delivers the Morphir CLI. The source is finos/morphir-dotnet, pinned as a submodule; this repository builds the four offerings with that source's own build, launches what it produced, and publishes releases that name their exact source, kit and artifact digests.

## ADDED Requirements

### Requirement: The CLI source is one pinned commit of finos/morphir-dotnet
The repository SHALL record the CLI source as a full 40-character commit of `https://github.com/finos/morphir-dotnet`, pinned as the `ecosystem/morphir-dotnet` submodule. A check SHALL fail when the submodule URL, its gitlink or the recorded commit disagree.

#### Scenario: The pin holds
- **WHEN** the gitlink of `ecosystem/morphir-dotnet` equals the recorded commit and `.gitmodules` names finos/morphir-dotnet
- **THEN** the source check passes and reports the repository and commit

#### Scenario: A moved gitlink is refused
- **WHEN** the gitlink differs from the recorded commit, or the recorded commit is abbreviated
- **THEN** the source check fails and names both values

### Requirement: Offerings come from the pinned source's own build
Every released artifact SHALL be produced by the pinned source's release profiles: Native AOT, self-contained and framework-dependent `morphir` for Windows x64/ARM64, macOS x64/ARM64 and Linux glibc x64/ARM64, and the portable `Morphir.Tool` package. This repository SHALL NOT package artifacts itself, and its expected offerings and platforms SHALL equal those the pinned build defines.

#### Scenario: The expectations drift from the pinned build
- **WHEN** the pinned source defines a deployment or platform that the expectations omit, or the reverse
- **THEN** the release tests fail before any release runs

### Requirement: Qualification launches the produced artifact
Each archive SHALL be qualified by extracting it and starting its executable or apphost directly, never through `dotnet exec`. The tool package SHALL be installed from the artifact and run as `dotnet-morphir` and as `dotnet morphir`. Offerings that carry their runtime SHALL run with no .NET on the search path. Each run SHALL check the version, the help and a packaged IR input.

#### Scenario: A launched executable reports the release version
- **WHEN** the Native AOT archive for `win-x64` is extracted and `morphir.exe --version` is started from the extracted folder
- **THEN** its output is the release version, alone or followed by `+` and at least 7 hex digits of the pinned source commit, and the launch scenario passes

#### Scenario: Build metadata from another commit
- **WHEN** the launched executable prints the release version with build metadata that is not a prefix of the pinned commit
- **THEN** the launch scenario fails

#### Scenario: The tool package keeps both invocations
- **WHEN** `Morphir.Tool` is installed from the produced package
- **THEN** both `dotnet-morphir --version` and `dotnet morphir --version` report the release version by the same rule

### Requirement: A recorded pending triage is never counted as qualified
A scenario result on a platform under a recorded pending triage SHALL be kept with its exit code and reported as `pending-triage`, and the offering SHALL NOT be reported as qualified on that platform. No scenario is under triage now: macOS qualifies the packaged input like every other platform.

#### Scenario: A scenario under triage passes
- **WHEN** a scenario recorded as pending triage on `osx-arm64` exits 0 there
- **THEN** its status is `pending-triage` and the offering's `qualified` flag is false on that platform

#### Scenario: macOS packaged input hangs
- **WHEN** the packaged-input scenario does not finish on `osx-arm64`
- **THEN** the scenario fails and the release is not published

### Requirement: Official CLI releases use v<version> and only ever move forward
An official CLI release SHALL be started only by a tag `v<version>`, or an explicit existing tag of that form. `<version>` SHALL be exact canonical SemVer without build metadata and equal the latest released version in the pinned CHANGELOG. The namespace is shared with the deleted Rust CLI's `v*` releases, which SHALL stay unchanged; publication SHALL be refused unless `<version>` is newer than every other `v*` tag in finos/morphir.

#### Scenario: The tag and the pinned CHANGELOG disagree
- **WHEN** `v0.4.0-beta.13` is pushed while the pinned CHANGELOG's latest release is `0.4.0-alpha.4`
- **THEN** the release stops before any build

#### Scenario: A version below the Rust CLI's releases
- **WHEN** the pinned source releases `0.4.0-alpha.4` and finos/morphir already has `v0.4.0-beta.12`
- **THEN** publication is refused because `v0.4.0-alpha.4` is not newer than `v0.4.0-beta.12`

#### Scenario: Another namespace
- **WHEN** a tag `cli/v0.4.0` or `extension/python/v0.4.0` is pushed
- **THEN** the release workflow does not run, or refuses the tag
### Requirement: A release is published once, with its evidence, and never replaced
The release SHALL be created only after every offering is qualified on every platform, in one step that attaches every artifact and a release manifest naming the tag, the finos/morphir commit, the source commit, the kit's corpus hash and revision from the shared runner, and each artifact's SHA-256. A tag whose release already exists SHALL be refused; nothing SHALL be uploaded into or replace an existing release, and no tag SHALL be created by the workflow.

#### Scenario: The release already exists
- **WHEN** the workflow runs for a tag whose GitHub release exists
- **THEN** it fails and the existing release and its assets are unchanged

#### Scenario: One platform failed qualification
- **WHEN** any offering's launch scenario fails on any platform
- **THEN** no release is created

### Requirement: The tool package is installed only from its own bytes
Qualification SHALL install the produced tool package through a generated NuGet configuration that clears every other source, with fresh global packages, HTTP and plugin caches, so no feed or cache with the same id and version can supply it. Every package copy NuGet keeps, in the tool store and in the packages folder, SHALL have the artifact's SHA-256; otherwise qualification fails.

#### Scenario: A conflicting package of the same id and version
- **WHEN** the working directory's NuGet configuration names a feed with another `Morphir.Tool` of the same version, and the environment's packages folder already holds it
- **THEN** both installs take the produced package and every kept copy has its SHA-256

#### Scenario: A kept copy differs
- **WHEN** a package copy in the tool store has another SHA-256 than the produced package
- **THEN** qualification fails and names the copy

### Requirement: Only the source's own release is published under its version
A release SHALL be created only when the pin is not a marked candidate, the pinned CHANGELOG has no entry under `Unreleased`, and the source repository's tag `v<version>` names exactly the pinned commit. Otherwise publication SHALL be refused, so unreleased source bytes are never published under a version the source already released. This repository SHALL NOT choose, bump or override the version.

#### Scenario: Unreleased source under an already released version
- **WHEN** the pin is `8c15df5`, its CHANGELOG has unreleased entries and the source's `v0.4.0-alpha.4` is `bec7df3`
- **THEN** publication is refused and the reasons are recorded

### Requirement: A run is bound to its tag, its commit and the pin
A publication SHALL run only from `refs/tags/<tag>` with the checkout at the tag's commit (a dry run MAY instead run from a branch, as the next requirement states), and the workflow's literal source commit in `uses` and `ref` SHALL equal the pin. Every later job SHALL check out that commit, and the manifest SHALL record it as read from the checkout. Every artifact's build contents SHALL name the pinned commit and a clean working tree, and SHALL match its launch metadata.

#### Scenario: A publication dispatched from a branch
- **WHEN** the workflow is dispatched from `main` with the input `v0.4.0-beta.13` and `dry-run: false`
- **THEN** release-info refuses before any build

#### Scenario: An artifact packed from another commit
- **WHEN** an artifact's build contents record a commit other than the pin
- **THEN** qualification and the manifest refuse it

### Requirement: A dry run may rehearse a release from a branch
A dry run MAY run from a branch (`refs/heads/...`), so a release can be rehearsed before its tag exists. Release-info SHALL then bind the run to the branch's triggering commit in place of the tag's commit, and every other binding SHALL hold. A run that is not a dry run SHALL NOT run from a branch.

#### Scenario: A rehearsal dispatched from a branch
- **WHEN** a dry run is dispatched from a branch with the input `v<version>`, where `<version>` is the latest release in the pinned CHANGELOG, before that tag exists in finos/morphir
- **THEN** release-info binds the run to the branch's triggering commit, the run builds and qualifies, and no release is created

### Requirement: A dry run validates everything and creates nothing
A dispatched run SHALL default to a dry run. A dry run SHALL perform every validation a publication performs, record the publication blockers, and write the manifest, the notes and the list of files it would attach as evidence, but SHALL NOT create a release. A validation failure SHALL fail a dry run as well.

#### Scenario: Dry run of the candidate pin
- **WHEN** the candidate pin is released as a dry run with every qualification passing
- **THEN** the evidence records `publishable: false` with the candidate as a blocker, and no release exists

### Requirement: Qualification records match the artifacts exactly
The manifest SHALL require exactly one qualification for each deployment and platform. Its release, artifact and SHA-256 SHALL equal the launch metadata of the artifact it launched. A missing, repeated, unexpected or mismatched record SHALL be refused.

#### Scenario: A qualification of other bytes
- **WHEN** a qualification records a SHA-256 other than its artifact's
- **THEN** no manifest is written