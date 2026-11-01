# Spec Delta

## Purpose

Lets an extension author release an extension, and a repository owner admit it into their index, with short default
setup and no long-lived publishing secret.

## ADDED Requirements

### Requirement: Short default setup
With the defaults, a publisher SHALL be able to start releasing with no more than three commands in total, and a
repository owner SHALL be able to create a repository and admit a publisher with no more than three commands in
total. Advanced options SHALL NOT be required for the default path.

#### Scenario: New publisher
- **WHEN** an author with a built extension follows the documented default path
- **THEN** their next release is published and admitted after at most three commands from them, plus one command from
  the repository owner

### Requirement: Publish in a release workflow
`morphir extension publish` SHALL run in a GitHub Actions workflow, assemble the extension's release bundle, run the
describe probe, create a GitHub release with the bundle and each artifact's GitHub artifact attestation, and SHALL
need no secret beyond the workflow's own token.

#### Scenario: Release run
- **WHEN** a tagged release workflow runs `morphir extension publish`
- **THEN** a GitHub release exists with the bundle, its descriptor and an attestation for each artifact

#### Scenario: Outside GitHub Actions
- **WHEN** `morphir extension publish` runs where no GitHub OIDC token is available
- **THEN** it fails and says that publishing needs a GitHub Actions workflow with `id-token: write`

### Requirement: Publisher workflow generation
`morphir extension publish setup` SHALL write a release workflow for the current repository with the permissions
publishing needs, and SHALL print the publisher identity to give the repository owner.

#### Scenario: Generate the workflow
- **WHEN** the author runs `morphir extension publish setup`
- **THEN** a workflow file is written and the output shows the owner/repo and workflow path to register

### Requirement: Repository creation
`morphir repository setup` SHALL prepare a GitHub repository to host an index: a protected index location, an empty
index, the registered-publisher list and the index admission workflow.

#### Scenario: Create a repository
- **WHEN** an owner runs `morphir repository setup` in their GitHub repository
- **THEN** the index location, publisher list and admission workflow exist, and the output gives the
  `morphir extension repository add` line for users

### Requirement: Registered publishers
A repository owner SHALL register, with one command, which publisher repository may publish which extension ids,
with the release workflow path recorded for later verification. The admission workflow SHALL admit a release only if
it comes from the registered publisher repository.

#### Scenario: Unregistered publisher
- **WHEN** a release of `morphir-cobol` comes from a repository the owner did not register for it
- **THEN** the admission workflow does not admit it and records why

### Requirement: Admission by the owner's workflow
The owner's admission workflow SHALL find new releases of registered publishers without any secret from them, verify
the digests and claims, add the entries to the index, record the digest of each changed history in the index root,
increase the index serial and attest the index.
A release SHALL appear in the index within one scheduled run.

#### Scenario: Scheduled admission
- **WHEN** a registered publisher creates a release
- **THEN** the next scheduled admission run adds it to the index, and users can install it

#### Scenario: Owner triggers admission
- **WHEN** the owner starts the admission workflow by hand
- **THEN** pending releases are admitted at once

### Requirement: Mirrored artifacts for the browser
The admission workflow SHALL be able to copy admitted artifacts to a location that allows cross-origin reads, and
SHALL record that location in the index entry, with the same digest.

#### Scenario: Browser location recorded
- **WHEN** an owner enables mirroring and a release is admitted
- **THEN** the index entry lists the mirrored location in addition to the release asset
