# Spec Delta

## Purpose

Lets the user decide, once and simply, which extension repositories and publishers the CLI may install from, and
verifies that artifacts and indexes come from the identities that trust names, while unattended runs can accept trust
ahead of time.

## ADDED Requirements

### Requirement: Trust belongs to the user
The CLI SHALL install an extension from a GitHub-hosted repository only when the user trusts that repository. The
`finos` repository SHALL be trusted by default. Trusting a repository SHALL mean trusting the publisher identities its
index names for its entries, including entries the owner admits later. Local-directory repositories SHALL need no
trust.

#### Scenario: Default trust
- **WHEN** a user with a fresh `MORPHIR_HOME` installs an extension from `finos`
- **THEN** no trust prompt appears

#### Scenario: Entry added after trust
- **WHEN** the owner of a trusted repository admits a new extension and the user installs it
- **THEN** no trust prompt appears

#### Scenario: Untrusted repository
- **WHEN** a user installs from `acme`, which they have not trusted, in a non-interactive run with no trust option
- **THEN** the install fails before any download and names `acme` and the command or option that trusts it

### Requirement: One trust prompt per operation
When an interactive operation needs trust that the user has not given, the CLI SHALL show one prompt listing every
new repository and publisher identity the operation needs, before downloading anything. The prompt SHALL offer: trust
all listed, choose items, continue with already-trusted items only, and cancel. `morphir setup` SHALL show it on its
review screen, and on-demand installation in compile and generate SHALL show it before installing.

#### Scenario: Several new items
- **WHEN** a setup selection needs two untrusted repositories
- **THEN** one prompt on the review screen lists both, with each repository's GitHub location and publisher identities

#### Scenario: Choose items
- **WHEN** the user chooses to trust only one of the listed repositories
- **THEN** extensions from the other repository are skipped and reported as skipped

### Requirement: Trust command
`morphir trust` SHALL add, list and remove trust for repositories. Adding trust SHALL show the repository's GitHub
location, its owner identity and the publisher identities in its index, and SHALL need one confirmation. Removing
trust SHALL NOT uninstall extensions; they keep working until they are updated.

#### Scenario: Trust ahead of time
- **WHEN** the user runs `morphir trust add acme`
- **THEN** later installs from `acme` show no prompt

#### Scenario: Revoke
- **WHEN** the user runs `morphir trust remove acme`
- **THEN** new installs and updates from `acme` need trust again, and installed `acme` extensions still run

### Requirement: Unattended trust
Every command that can prompt for trust SHALL accept options that give the answer ahead of time: trust named
repositories, or trust every repository the operation needs. A run that is not interactive and lacks a needed answer
SHALL fail before downloading anything.

#### Scenario: CI setup
- **WHEN** CI runs `morphir setup --defaults --trust acme`
- **THEN** the run completes without a prompt and records the trust for `acme`

### Requirement: Trust is recorded with what was shown
The CLI SHALL store each trust decision under `MORPHIR_HOME` with the time, the repository location, the owner
identity and the publisher identities that were shown. If a later index names a different publisher identity for an
installed extension, the CLI SHALL ask for trust again before updating it, for every repository including `finos`.

#### Scenario: Publisher identity changes
- **WHEN** the `acme` index starts naming a different signing workflow for the installed `morphir-cobol`
- **THEN** updating `morphir-cobol` asks for trust again and shows the old and new identities

#### Scenario: Owner identity shown on first trust
- **WHEN** the user trusts a repository other than `finos`
- **THEN** the prompt shows the owner identity taken from its index, and the record keeps it

### Requirement: Verified artifacts
For a GitHub-hosted repository, the CLI SHALL verify each artifact's GitHub artifact attestation against the
publisher identity in the trusted index before the artifact enters the store, and SHALL record the verified bundle in
the lock. A missing or failing attestation SHALL stop the install and leave the previous state unchanged.

#### Scenario: Attestation from another workflow
- **WHEN** the artifact's attestation was signed by a workflow other than the one the index names
- **THEN** the install fails, names both identities, and nothing is stored

#### Scenario: Provenance offline
- **WHEN** the user runs `morphir extension list --json` with no network
- **THEN** each extension from a GitHub-hosted repository shows its verified publisher identity

### Requirement: Verified indexes
For a GitHub-hosted repository, the CLI SHALL install only from an index whose owner attestation verifies against the
trusted owner identity. It SHALL read a per-extension history only when its digest equals the digest in that verified
index, so that the owner attestation covers every publisher identity, artifact location and artifact digest that
resolution reads. It SHALL still list the entries of an unverified index in search results, marked as not installable.

#### Scenario: Forged index
- **WHEN** a GitHub-hosted index carries no attestation from the trusted owner identity
- **THEN** search shows its entries as not installable, and an install from it fails with the reason

#### Scenario: Modified history under a valid index
- **WHEN** the attestation on `index.json` verifies, but a per-extension history names another publisher and differs
  from the digest in `index.json`
- **THEN** the install fails with the reason, and no artifact from that history is fetched or run

### Requirement: Verified admission
The owner's admission workflow SHALL admit a release only when each artifact's attestation verifies against the
registered publisher repository and release workflow.

#### Scenario: Release from an unregistered workflow
- **WHEN** a release in a registered publisher repository was attested by a workflow the owner did not register
- **THEN** the admission workflow does not admit it and records why
