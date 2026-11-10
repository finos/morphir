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
A scenario result on a platform under a recorded pending triage SHALL be kept with its exit code and reported as `pending-triage`, and the offering SHALL NOT be reported as qualified on that platform. The macOS packaged-input scenario is under such a triage (the `/var` to `/private/var` failure seen in finos/morphir-dotnet#570, workflow run 42851276092).

#### Scenario: macOS packaged input passes
- **WHEN** the packaged-input scenario exits 0 on `osx-arm64`
- **THEN** its status is `pending-triage` and the offering's `qualified` flag is false on that platform

### Requirement: Official CLI releases have their own tag namespace
An official CLI release SHALL be started only by a tag `cli/v<version>` or an explicit existing tag of that form, where `<version>` is exact canonical SemVer without build metadata and equals the latest released version in the pinned source's CHANGELOG. Tags of the deleted Rust CLI (`v*`) SHALL NOT start a release.

#### Scenario: A Rust CLI tag is pushed
- **WHEN** a tag `v0.4.0-beta.13` is pushed
- **THEN** the release workflow does not run

#### Scenario: The tag and the pinned CHANGELOG disagree
- **WHEN** `cli/v0.4.0-alpha.5` is pushed while the pinned CHANGELOG's latest release is `0.4.0-alpha.4`
- **THEN** the release stops before any build

### Requirement: A release is published once, with its evidence, and never replaced
The release SHALL be created only after every offering is qualified on every platform, in one step that attaches every artifact and a release manifest naming the tag, the finos/morphir commit, the source commit, the kit's corpus hash and revision from the shared runner, and each artifact's SHA-256. A tag whose release already exists SHALL be refused; nothing SHALL be uploaded into or replace an existing release, and no tag SHALL be created by the workflow.

#### Scenario: The release already exists
- **WHEN** the workflow runs for a tag whose GitHub release exists
- **THEN** it fails and the existing release and its assets are unchanged

#### Scenario: One platform failed qualification
- **WHEN** any offering's launch scenario fails on any platform
- **THEN** no release is created
