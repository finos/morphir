# Spec Delta

## Purpose

Lets the CLI find extensions in named repositories that their owners curate, hosted on GitHub or in a local
directory, by extension id or by the capability a user needs.

## ADDED Requirements

### Requirement: Default finos repository
The CLI SHALL come with one repository configured and enabled: `finos`, whose index the finos/morphir repository
publishes. A user SHALL be able to disable it but SHALL NOT need any command to use it.

#### Scenario: Fresh home has the finos repository
- **WHEN** a user runs `morphir extension repository list` with an empty `MORPHIR_HOME`
- **THEN** the output lists `finos` as enabled, with its GitHub location

#### Scenario: Disabled default repository is not consulted
- **WHEN** the user disables `finos` and runs `morphir extension search elm`
- **THEN** no result comes from `finos`

### Requirement: Add a GitHub-hosted repository in one command
A user SHALL be able to add a GitHub-hosted repository with one command that names the GitHub owner and repository,
with an optional branch and path. The CLI SHALL read the index once to confirm it is a Morphir extension index, and
SHALL refuse anything else without saving configuration.

#### Scenario: Add a community repository
- **WHEN** the user runs `morphir extension repository add acme github:acme/morphir-repo`
- **THEN** `acme` is saved and enabled, and its extensions appear in search

#### Scenario: Not an index
- **WHEN** the named GitHub location has no Morphir extension index
- **THEN** the command fails with a message naming the location, and no repository is saved

### Requirement: Local-directory repositories
The CLI SHALL keep supporting repositories in a local directory, for development, tests and air-gapped use, with the
same index content as a GitHub-hosted repository.

#### Scenario: Air-gapped install
- **WHEN** a user adds a local directory that holds a copy of an index and its artifacts, and installs from it with
  no network
- **THEN** the install succeeds without any network request

### Requirement: Index content
A repository index SHALL state, for each extension version: the extension id and version, its capability claims
(roles, languages, targets, IR versions), each artifact with its runtime, platform, location and SHA-256 digest, and
its release channel. It SHALL also state the repository's recommended extensions and an index serial number. An entry
MAY name the publisher identity that released it; the CLI SHALL show it when present.

#### Scenario: Entry without an artifact digest
- **WHEN** an index entry has an artifact with no SHA-256 digest
- **THEN** the CLI treats the entry as unusable, says why, and does not offer it for installation

### Requirement: Index root binds its histories
The index root SHALL state the SHA-256 digest of every per-extension history. The CLI SHALL refuse to read a history
whose digest differs from the digest in the root.

#### Scenario: History that does not match the root
- **WHEN** a per-extension history differs from the digest that the index root states for it
- **THEN** the CLI refuses that history, says why, and offers none of its entries

### Requirement: Search by name and by capability
`morphir extension search` SHALL match extension ids and display names. The CLI SHALL also answer a capability query:
which extensions in enabled repositories provide a role for a language or target at an IR version, on the current
platform and host. Every result SHALL name its repository.

#### Scenario: Capability query
- **WHEN** the CLI needs `frontend.compile` for language `elm` at IR 4
- **THEN** it returns each matching extension version with its repository, publisher when recorded, and channel

#### Scenario: Platform mismatch
- **WHEN** an extension version has only a process artifact for another platform
- **THEN** it is not a capability result on this platform

### Requirement: Index freshness
The CLI SHALL record, for each repository, the highest index serial it has accepted, and SHALL refuse an index with
a lower serial.

#### Scenario: Rolled-back index
- **WHEN** a repository serves an index with a serial lower than the one the CLI last accepted
- **THEN** the CLI refuses it, keeps the last accepted index, and reports the rollback

### Requirement: Cached indexes and offline use
The CLI SHALL cache each accepted index under `MORPHIR_HOME`, refresh it only when an operation needs current
repository data, and SHALL use the cached index when the network is unavailable, saying that it did.

#### Scenario: Offline search
- **WHEN** the network is unavailable and the user searches
- **THEN** results come from the cached indexes, with a note that they may be out of date

### Requirement: No trust step
Using any enabled repository SHALL NOT require a trust decision, prompt or option in this change. Enabling or adding
a repository is the user's choice to use it.

#### Scenario: Community repository without trust
- **WHEN** the user adds `acme` and installs one of its extensions
- **THEN** no trust prompt appears and no trust option is needed
