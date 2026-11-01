# Spec Delta

## Purpose

Defines how the CLI turns a selected extension version into checked, recorded local state under `MORPHIR_HOME`, and
how it later starts that extension without the network.

## ADDED Requirements

### Requirement: Install in one command
`morphir extension install <id>` SHALL resolve the extension from the enabled repositories without naming a
repository, as long as exactly one enabled repository offers it. With more than one, it SHALL list them and require
`--repository`. `--channel` and `--version` SHALL select a channel or an exact version; the default is `stable`.

#### Scenario: Default install
- **WHEN** the user runs `morphir extension install morphir-gleam`
- **THEN** the newest stable version for this platform and host is installed from `finos`

#### Scenario: Ambiguous source
- **WHEN** both `finos` and `acme` offer `morphir-cobol`
- **THEN** the command lists both repositories and asks for `--repository`

### Requirement: Check the digest before storing
Before an artifact enters the store, the CLI SHALL check its SHA-256 digest against the index entry. A mismatch SHALL
stop the install with the reason and SHALL leave the previous state unchanged.

#### Scenario: Digest mismatch
- **WHEN** the downloaded bytes do not match the indexed digest
- **THEN** the install fails, names both digests, and nothing is stored

### Requirement: Probe the claims
After the digest check and before the extension is recorded, the CLI SHALL run the extension's describe probe through
the extension host, and SHALL refuse the install if the extension's identity, version or capabilities differ from the
index entry.

#### Scenario: Claims differ
- **WHEN** the probe reports a language the index did not claim
- **THEN** the install is refused and the difference is reported

### Requirement: Versioned home layout
The CLI SHALL keep extension state under `MORPHIR_HOME` in a layout that carries a layout version, with a
content-addressed store, an installed catalog and a lock per installed extension. It SHALL NOT read, change or delete
extension state written by the Rust CLI.

#### Scenario: Home used by the Rust CLI
- **WHEN** `MORPHIR_HOME` holds extensions installed by the Rust CLI
- **THEN** `morphir extension list` shows none of them, and their files are untouched

### Requirement: Lock records the selection
Each lock SHALL record the repository, the index serial, the selected id, version and channel, each artifact's
location and digest, and the publisher identity when the index names one, so that the CLI can show provenance
without the network.

#### Scenario: Show provenance offline
- **WHEN** the user runs `morphir extension list --json` with no network
- **THEN** each extension shows its repository, version and digest

### Requirement: Offline activation
Starting an installed extension SHALL use only local state: the CLI SHALL check that the catalog and lock agree,
rehash the stored artifact, and compare the session handshake with the recorded claims before sending any operation.

#### Scenario: Changed file
- **WHEN** a stored artifact was modified after installation
- **THEN** activation fails with a digest error before the extension runs

### Requirement: Update and uninstall
`morphir extension update <id>` SHALL install a newer version with the same checks and replace the active version
only after it passes. `morphir extension uninstall <id>` SHALL remove the extension from the catalog; stored content
MAY stay in the cache.

#### Scenario: Failed update
- **WHEN** the newer version fails its digest check or probe
- **THEN** the installed version stays active and the failure is reported

### Requirement: No helper flags
The extension lifecycle commands SHALL NOT require `--services-pin`, `--services-helper` or any other helper
executable or pin from the user.

#### Scenario: Plain install
- **WHEN** the user runs `morphir extension install morphir-gleam` with no other flags
- **THEN** the command runs without asking for a helper or pin

### Requirement: Hosts that cannot start processes
On a host that cannot start processes, such as a browser, the CLI SHALL offer only portable (WASM) artifacts, and
SHALL download them only from locations that allow cross-origin reads. An entry with no such artifact or location
SHALL be reported as not installable on that host, with the reason.

#### Scenario: Release asset without CORS
- **WHEN** the only location of a WASM artifact is a GitHub release asset and the host needs cross-origin reads
- **THEN** the CLI reports that the extension cannot be installed on this host and names the missing mirror

#### Scenario: Native-only extension
- **WHEN** an extension has only native process artifacts and the host cannot start processes
- **THEN** it is not offered on that host
