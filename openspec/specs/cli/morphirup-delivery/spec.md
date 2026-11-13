# cli/morphirup-delivery Specification

## Purpose
Defines how a finos/morphir release delivers morphirup, the Morphir toolchain manager, and the setup toolchains it installs. Both are built from the pinned finos/morphir-dotnet source by that source's own workflow and build targets, and attached under the same names a finos/morphir-dotnet release of the same version gives them. morphirup reads its release source by those names.

Example: the release `v0.5.0-alpha.2` attaches `morphirup-win-arm64.exe`, `morphirup-v0.5.0-alpha.2.sha256`, `morphir-toolchain-win-arm64.json`, `morphir-dotnet-0.5.0-alpha.2-self-contained-win-arm64.zip` and `SHA256SUMS`, among the others. `SHA256SUMS` lists the host archive with the bytes the release attaches.

## Requirements

### Requirement: A release attaches the morphirup and toolchain assets under the source's names
A finos/morphir release `v<version>` SHALL attach exactly the morphirup and setup-toolchain assets of the pinned source: the manager and its archive for each morphirup platform, the morphirup checksum file and notices, the complete setup toolchain of each toolchain platform, and one `SHA256SUMS`. Their names SHALL be those a finos/morphir-dotnet release of `version` gives them. A missing, extra or renamed asset SHALL fail the release.

#### Scenario: The names of v0.5.0-alpha.1
- **WHEN** the expected morphirup assets of `0.5.0-alpha.1` are listed
- **THEN** they are the 43 assets of the finos/morphir-dotnet `v0.5.0-alpha.1` release that are not legacy CLI names

#### Scenario: An extra toolchain file
- **WHEN** the assembled assets include a file the contract does not name
- **THEN** the manifest step refuses the release

### Requirement: The source's own workflow and targets build and assemble them
The assets SHALL be built by the pinned source's reusable `morphirup-build.yml`, called at the pinned commit with that commit as its `ref`. They SHALL be assembled by the source's own release targets run from the pinned checkout, with both checksum files read back. Every checksum entry SHALL name a release asset with its bytes.

#### Scenario: A checksum entry with other bytes
- **WHEN** `SHA256SUMS` lists a toolchain file with a SHA-256 the attached file does not have
- **THEN** the release is refused

### Requirement: A host archive is attached once, as its platform's self-contained offering
On a toolchain platform, the self-contained offering SHALL be the toolchain job's host archive, so the release attaches one file under that name. Its bytes SHALL be those the host candidate, the bundle and `SHA256SUMS` name.

#### Scenario: Two builds under one name
- **WHEN** the self-contained offering of win-x64 differs from the host archive the toolchain names
- **THEN** the release is refused

### Requirement: Each manager and each toolchain is qualified on its own platform
Each morphirup manager SHALL be started on its own platform as a user starts it, with no .NET on the search path. Its `--version` SHALL name the release built from the pinned commit, and its archive SHALL hold the same executable. The source's acquired setup journey SHALL pass on each toolchain platform before the release is published. The manifest SHALL record every manager qualification and the setup journey.

#### Scenario: A manager that reports another release
- **WHEN** a morphirup manager's `--version` names another release or commit
- **THEN** its qualification fails and no release is created

#### Scenario: A failed setup journey
- **WHEN** the setup journey fails on osx-arm64
- **THEN** the morphirup job of osx-arm64 fails and nothing is published
