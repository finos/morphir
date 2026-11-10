# Spec Delta

## Purpose

Defines the identity of a Morphir extension: the grammar of its id, how ids are compared, what an id does and does not mean, the file and key names a host derives from it, the contract versions that carry the new grammar, and the shared home and repository files that installers sharing a Morphir home must agree on. Every host, repository and toolchain contract that names an extension follows it.

An id is one or more segments joined by `.`. `morphir-elm` has one segment. `org.finos.morphir.fsharp-frontend` has four, in reverse-DNS style. Both are valid, both are compared byte for byte, and neither says anything about who published the extension.

| Id | Valid | Why |
| --- | --- | --- |
| `morphir-elm` | yes | one segment |
| `org.finos.morphir.fsharp-frontend` | yes | four segments |
| `morphir.csharp` | yes | two segments |
| `a..b` | no | empty segment |
| `Org.finos` | no | uppercase |
| `con.example` | no | first segment is a Windows device name |

Two installers share a home when they read and write the same `MORPHIR_HOME`. They agree only if they read and write the same shared files the same way. The shared files are:

| File | Path | Version | Unknown members |
| --- | --- | --- | --- |
| Release descriptor | `release.json` in a release | `2.0.0-draft.3` | ignored unless named in `critical` |
| Index record | one line of `extensions/<id>.jsonl` in a repository | `2.0.0-draft.3` | ignored unless named in `critical` |
| Installed catalog | `catalog/extensions.json` | `2.0.0-draft.3` | ignored unless named in `critical` |
| Extension lock | `locks/extensions/<id>.json` | `2.0.0-draft.1` | refused |
| Transaction journal | `locks/extensions/<id>.json.transaction` | `2.0.0-draft.1` | refused |
| Repositories configuration | `config/extensions/repositories.json` | `1` | refused |
| State lock | `locks/extensions.state.lock` | none, no content | not applicable |
| Repositories lock | `locks/extensions.repositories.lock` | none, no content | not applicable |

Paths in the home are relative to the home root, and paths in a repository are relative to the repository root.

## ADDED Requirements

### Requirement: An extension id is a dotted portable token
An extension id SHALL be one or more segments joined by `.`. Each segment SHALL start with a lowercase ASCII letter, contain only lowercase ASCII letters, digits and `-`, and end with a lowercase ASCII letter or digit. An id SHALL have at most 238 characters in total, counting the dots. A segment has no length limit of its own.

#### Scenario: Valid ids
- **WHEN** a reader reads the ids `morphir-elm`, `a`, `morphir.csharp`, `acme.tools.lint-2` and `org.finos.morphir.fsharp-frontend`
- **THEN** each one is accepted as an extension id

#### Scenario: Invalid ids
- **WHEN** a reader reads the ids `""`, `.`, `..`, `a..b`, `.a`, `a.`, `A`, `a.B`, `1a`, `a.1b`, `a-`, `a.b-`, `a_b`, `a b` and `a/b`
- **THEN** each one is refused under the rule `grammar`, and the refusal names the id and that rule

#### Scenario: Length boundary
- **WHEN** a reader reads a valid id of exactly 238 characters and the same id with one more letter appended
- **THEN** the first is accepted and the second is refused under the rule `length`

### Requirement: The first segment of an id is not a Windows device name
An extension id SHALL be refused when its first segment is `con`, `prn`, `aux`, `nul`, or `com` or `lpt` followed by a single digit from `1` to `9`. Later segments are not restricted by this rule. `com0` and `lpt0` are not device names under this rule. The superscript device forms such as `COM¹` cannot occur in an id, because the grammar admits only ASCII.

#### Scenario: Device names in the first segment
- **WHEN** a reader reads the ids `con`, `nul.tools`, `com1.lint` and `lpt9`
- **THEN** each one is refused under the rule `device-name`

#### Scenario: Device names in later segments
- **WHEN** a reader reads the ids `acme.con`, `acme.nul.tools` and `console.tools`
- **THEN** each one is accepted

#### Scenario: Digit zero is not a device number
- **WHEN** a reader reads the ids `com0.tools` and `lpt0`
- **THEN** each one is accepted

### Requirement: A refusal names the first rule the id breaks
A reader that refuses an id SHALL name exactly one rule: the first of `grammar`, `length` and `device-name`, checked in that order, that the id breaks. Shared cases record the outcome and that rule name.

#### Scenario: An id that breaks several rules
- **WHEN** a reader reads `con..x`, a 239-character id that contains `_`, and a 239-character id that matches the grammar and starts with `con.`
- **THEN** it refuses them under `grammar`, `grammar` and `length` respectively

### Requirement: Every existing single-segment id keeps its meaning
Every id that is valid under the single-token rule of descriptor `2.0.0-draft.2` SHALL be valid under this rule and SHALL denote the same extension.

#### Scenario: Published ids stay valid
- **WHEN** a reader reads the published ids `morphir-elm`, `morphir-elm-classic`, `morphir-elm-native`, `morphir-rust`, `morphir-python`, `morphir-avro`, `morphir-openapi` and `morphir-scala-elm`
- **THEN** each one is accepted and names the same extension as before

### Requirement: Extension ids are compared exactly
Two extension ids SHALL be equal only when their bytes are equal. A reader SHALL NOT fold case, normalize, or treat `.` and `-` as interchangeable when it compares or indexes ids.

#### Scenario: A dot and a hyphen are different ids
- **WHEN** a repository holds extensions with the ids `morphir.elm` and `morphir-elm`
- **THEN** a host treats them as two different extensions and lists both

### Requirement: The descriptor id equals the claims id and the session id
The `extensionId` of a release descriptor, the `extension.id` of every artifact's capability claims and the `extension.id` an artifact reports in a MEP session SHALL be byte-for-byte equal. A dotted id SHALL NOT be shortened, mapped or replaced by a single token anywhere a release, record, lock or session names the extension.

#### Scenario: A descriptor whose claims name another spelling is refused
- **WHEN** a release descriptor has `extensionId` `org.finos.morphir.fsharp-frontend` and an artifact's claims have `extension.id` `morphir-fsharp-frontend`
- **THEN** bundle authoring, publication and installation each refuse the release

#### Scenario: A session that reports another id is refused
- **WHEN** an installed extension recorded as `org.finos.morphir.fsharp-frontend` reports `org.finos.morphir.fsharp-backend` at initialization
- **THEN** the host rejects the session before calling the extension

### Requirement: An extension id carries no trust
A reverse-DNS style id SHALL be treated as a name only. A host or repository SHALL NOT verify, infer or rely on ownership of a domain from an id. It SHALL NOT grant trust, permissions, precedence or a built-in status because of an id's segments. Publisher authentication and claim checks SHALL be decided by their own mechanisms, whatever the id.

#### Scenario: A familiar prefix grants nothing
- **WHEN** an unsigned developer artifact identifies itself as `org.finos.morphir.fsharp-frontend`
- **THEN** it is still an unsigned developer artifact, admitted only under explicit developer policy, and its claim check is still decided by the probe
- **AND** no host treats it as published by FINOS because of its id

### Requirement: A host may refuse ids under a prefix it keeps for its built-ins
A host MAY refuse to install an extension whose id falls under a prefix that the host keeps for its own built-in frontends and backends. Such a refusal SHALL grant nothing to any id, and SHALL NOT be used to give an installed extension trust, precedence or built-in status.

#### Scenario: A prefix kept for built-ins is a refusal, not a grant
- **WHEN** a host that keeps every id starting with `morphir.` for its built-ins is asked to install a release whose id is `morphir.example`
- **THEN** it refuses the install, and no installed extension gains trust, precedence or built-in status from any id

### Requirement: Names derived from an id are the id with a fixed suffix
Wherever a host or repository derives a file name from an extension id, it SHALL use the whole id followed by a fixed suffix, such as `<id>.jsonl`, `<id>.json` or `<id>.json.transaction`. Two different ids SHALL never derive the same name. The content-addressed artifact store SHALL NOT use the id in its paths.

#### Scenario: Derived names do not collide
- **WHEN** a host installs `acme.tools` and `acme-tools` and records their locks
- **THEN** it writes the two locks as `locks/extensions/acme.tools.json` and `locks/extensions/acme-tools.json`, and no name it derives for one equals a name it derives for the other on any first-delivery platform, including case-insensitive file systems

#### Scenario: A repository history is found by its full id
- **WHEN** a repository index holds `extensions/org.finos.morphir.fsharp-frontend.jsonl`
- **THEN** a reader takes the id `org.finos.morphir.fsharp-frontend` from the file name without its final `.jsonl`, and refuses the file if its records name another id

### Requirement: One catalog, one lock directory and one history directory hold every id
A Morphir home SHALL record every installed extension, whatever the form of its id, in the one catalog `catalog/extensions.json` and the one lock directory `locks/extensions/`. The catalog's `extensions` member SHALL be an array of entries, each naming its extension in its `extensionId` member, with each id at most once and the entries in ascending byte order of `extensionId`. A repository index SHALL keep every history in `extensions/<id>.jsonl`.

#### Scenario: A dotted install beside a single-segment one
- **WHEN** a host installs `org.finos.morphir.fsharp-frontend` into a home that holds `morphir-elm`
- **THEN** the `extensions` array of `catalog/extensions.json` holds two entries, `morphir-elm` first, and the new lock is `locks/extensions/org.finos.morphir.fsharp-frontend.json`

### Requirement: State changes are made under the state lock
A host SHALL take the state lock `locks/extensions.state.lock` before it replays a journal or reads, writes or removes the catalog, a lock or a journal, and SHALL hold it until the last of those writes and removals is complete. A host SHALL take the repositories lock `locks/extensions.repositories.lock` in the same way around every read-modify-write of `config/extensions/repositories.json`.

#### Scenario: Two hosts exclude each other
- **WHEN** one process holds the state lock of a home and a process of another host implementation starts an install into the same home
- **THEN** the second process reads and writes no catalog, lock or journal until the first releases the state lock

### Requirement: The lock primitive is a whole-file exclusive operating-system lock
A host SHALL take both lock files with one primitive: on Unix, `flock` with `LOCK_EX` on a descriptor open on the file; on Windows, `LockFileEx` with `LOCKFILE_EXCLUSIVE_LOCK` from offset 0 over a length of `0xFFFFFFFF` low and `0xFFFFFFFF` high. A host SHALL create a lock file that is absent, SHALL NOT write content to it, and SHALL NOT remove it.

#### Scenario: A record lock does not count
- **WHEN** a host on Linux takes the state lock
- **THEN** it calls `flock` with `LOCK_EX`, so that another host's `flock` on the same file waits, and it does not rely on an `fcntl` record lock

### Requirement: Shared documents are UTF-8 JSON compared by members
Every shared JSON document SHALL be UTF-8 without a byte order mark. Two installers SHALL be treated as conforming when they write equal members and values; their bytes need not be equal.

#### Scenario: Different spacing, same document
- **WHEN** two hosts write the same catalog entries with different indentation and member order
- **THEN** each host reads the other's catalog as the same catalog

### Requirement: Documents that carry a claim set ignore unknown members unless critical
A reader of a release descriptor, an index record or an installed catalog SHALL ignore a member it does not understand unless the document's `critical` list names it, and SHALL refuse a document whose `critical` list names a member it does not understand.

#### Scenario: An unknown member in an open document
- **WHEN** a host reads a `2.0.0-draft.3` catalog whose entry holds an optional member `note` that it does not understand, and another catalog whose `critical` list names `note`
- **THEN** it reads the first catalog and ignores `note`, and refuses the second

### Requirement: Locks, journals and the repositories configuration refuse unknown members
A reader of an extension lock, a transaction journal or the repositories configuration SHALL refuse a document that holds a member the contract does not define for it, and SHALL name the file and the member.

#### Scenario: An unknown member in a closed document
- **WHEN** a host reads a `2.0.0-draft.1` extension lock that holds a member `installedBy`
- **THEN** it refuses the lock and names the file and the member

### Requirement: Writers spell repository paths as ordinary absolute paths
A writer SHALL write `endpoint.path` in the repositories configuration and `index.identity` in a lock as the repository root's absolute path with symbolic links resolved, as `realpath` (Unix) or `GetFinalPathNameByHandleW` with `FILE_NAME_NORMALIZED` (Windows) reports it. It SHALL NOT write the verbatim prefix `\\?\`, SHALL write `\\?\UNC\server\share\…` as `\\server\share\…`, and SHALL write a drive letter in uppercase.

#### Scenario: A writer drops the verbatim prefix
- **WHEN** a host on Windows adds the local repository `C:\ext-repo` and the operating system reports its final path as `\\?\C:\ext-repo`
- **THEN** the host writes `C:\ext-repo` as `endpoint.path`

### Requirement: Readers read a verbatim path as the plain path
A reader SHALL read a path that carries the verbatim prefix as the same path without it, reading `\\?\UNC\server\share\…` as `\\server\share\…`, and SHALL compare two repository paths by their bytes after that rule.

#### Scenario: A verbatim path names the same repository
- **WHEN** a home's repositories configuration names a repository at `\\?\C:\ext-repo` and a lock's `index.identity` is `C:\ext-repo`
- **THEN** a host treats both as the same repository, and when it next writes either file it writes `C:\ext-repo`

### Requirement: Shared files are replaced through temporary files that readers ignore
A writer SHALL replace a shared file by writing a temporary file in the same directory, flushing it, and renaming it over the target. A temporary file's name SHALL start with `.stage-`. A reader that lists `locks/extensions/`, `catalog/` or a repository's `extensions/` SHALL ignore every entry whose name starts with `.`, and every entry that is not a regular file. No name derived from an id starts with `.`.

#### Scenario: A temporary file is not a journal
- **WHEN** a host takes the state lock and finds `locks/extensions/.stage-3f2a` and `locks/extensions/morphir-elm.json.transaction`
- **THEN** recovery considers only `morphir-elm.json.transaction` and leaves `.stage-3f2a` in place

### Requirement: The transaction journal has a fixed version and encoding
A host SHALL journal each change to an extension's lock and the catalog in `locks/extensions/<id>.json.transaction` before it writes either file. The journal SHALL have exactly the members `schemaVersion`, `nextLock` and `nextCatalog`. `schemaVersion` SHALL be the string `2.0.0-draft.1`. `nextLock` and `nextCatalog` SHALL each be present, and each SHALL be `null`, meaning the file is to be absent, or an array of integers from 0 to 255 holding the file's exact bytes.

#### Scenario: A journal of an install
- **WHEN** a host installs `morphir-elm` and has written its journal but not yet the lock
- **THEN** `locks/extensions/morphir-elm.json.transaction` has `schemaVersion` `2.0.0-draft.1` and holds the new lock's and the new catalog's bytes as arrays of integers

### Requirement: Recovery checks a journal before it writes
Recovery SHALL run under the state lock before any read of the catalog or a lock. For each journal it SHALL check that the journal is at `2.0.0-draft.1`, that a saved lock is valid JSON at `2.0.0-draft.1`, and that a saved catalog is valid JSON at `2.0.0-draft.3`. When a check fails, recovery SHALL refuse the journal, name it, and write nothing. Otherwise it SHALL write the lock, then the catalog, then remove the journal.

#### Scenario: An interrupted install is completed
- **WHEN** a host takes the state lock and finds a `2.0.0-draft.1` journal for `morphir-elm` whose saved lock and catalog are at the current drafts
- **THEN** it writes `locks/extensions/morphir-elm.json` and `catalog/extensions.json` with the saved bytes and removes the journal

#### Scenario: A journal at an earlier version is refused
- **WHEN** a host takes the state lock and finds a journal whose `schemaVersion` is the integer `1`
- **THEN** it refuses the journal, names it, and writes nothing

#### Scenario: A journal that would restore an earlier document is refused
- **WHEN** a host finds a `2.0.0-draft.1` journal whose `nextCatalog` holds the bytes of a `2.0.0-draft.2` catalog
- **THEN** it refuses the journal, names it, and writes neither the lock nor the catalog

### Requirement: The documents that can carry a dotted id are at new exact drafts
A writer SHALL write every release descriptor, repository index record and installed catalog at `2.0.0-draft.3`, and every extension lock at `2.0.0-draft.1`, whatever the form of the ids it names. `2.0.0-draft.3` differs from `2.0.0-draft.2` only in the id grammar, and the lock's `2.0.0-draft.1` differs from `"1.0"` only in the id grammar.

#### Scenario: A single-segment release is written at the new draft
- **WHEN** a publisher authors a release with the id `morphir-elm`
- **THEN** its descriptor has `schemaVersion` `2.0.0-draft.3`

#### Scenario: A single-segment index record and lock are written at the new drafts
- **WHEN** a publisher adds a `morphir-elm` release to a repository, and a host installs it
- **THEN** the new line of `extensions/morphir-elm.jsonl` has `schemaVersion` `2.0.0-draft.3`, and `locks/extensions/morphir-elm.json` has `schemaVersion` `2.0.0-draft.1`

#### Scenario: An earlier version is refused before any id is read
- **WHEN** a reader reads a `2.0.0-draft.2` descriptor or a `"1.0"` lock that names `org.finos.morphir.fsharp-frontend`
- **THEN** it refuses the document as an unsupported extension schema version, as it refuses the same document naming `morphir-elm`

### Requirement: A reader reads only the current drafts
A reader SHALL read `2.0.0-draft.3` descriptors, index records and catalogs, and `2.0.0-draft.1` locks and journals, and SHALL NOT read any other version of them, including `"1.0"`, major 1, `2.0.0-draft.1` and `2.0.0-draft.2` descriptors, records and catalogs, `"1.0"` locks and journals at version `1`. No conversion between versions is part of this contract. A reader that meets another version SHALL refuse the document, naming the file and the versions it reads.

#### Scenario: A current host meets an earlier descriptor
- **WHEN** a current host reads a release whose descriptor is at `2.0.0-draft.2`
- **THEN** it refuses the release as an unsupported extension schema version, names `release.json` and the version `2.0.0-draft.3`, and installs nothing

### Requirement: A repository history is read whole and holds one version
A reader SHALL read a history `extensions/<id>.jsonl` whole. Lines are separated by LF and numbered from 1; a line that holds only JSON whitespace is skipped but still counted. When any line is not a `2.0.0-draft.3` index record, the reader SHALL refuse the whole file, name the file and the number of the first such line, and select no release from it.

#### Scenario: A history with earlier lines is refused
- **WHEN** a reader reads `extensions/morphir-elm.jsonl` whose lines 1 and 2 are `2.0.0-draft.2` records and whose line 3 is a `2.0.0-draft.3` record
- **THEN** it refuses the file, names it and line 1, and resolves no `morphir-elm` release from it

### Requirement: A publisher does not append to a history at another version
A publisher SHALL NOT append a `2.0.0-draft.3` record to a history that holds a line at another version. It SHALL refuse the publication, name the file and the first such line, and leave the file unchanged.

#### Scenario: A publisher does not create a mixed history
- **WHEN** a publisher adds a `2.0.0-draft.3` release of `morphir-elm` to a repository whose `extensions/morphir-elm.jsonl` holds `2.0.0-draft.2` lines
- **THEN** it refuses the publication, names the file and its first earlier line, and leaves the file unchanged

### Requirement: A home that an older host wrote holds old state
Provisional on open question `Q-OLDHOME`, under every outcome. A home SHALL be treated as holding old state when its `catalog/extensions.json` is not at `2.0.0-draft.3`, or when `locks/extensions/` holds a lock or a journal that is not at `2.0.0-draft.1`. A host SHALL NOT read, replay or convert old state. Outcome `OLDHOME-C`, converting old state in place, contradicts the decision that transient drafts are not converted, so this change specifies no conversion.

#### Scenario: Old state is found by version
- **WHEN** a current host takes the state lock in a home whose catalog is at `2.0.0-draft.3` and whose `locks/extensions/morphir-elm.json` is at `"1.0"`
- **THEN** it treats the home as holding old state, naming `locks/extensions/morphir-elm.json`

### Requirement: A current host refuses old state and names one command
Provisional on `Q-OLDHOME`; this is outcome `OLDHOME-A`. A host SHALL refuse every command that reads or writes extension state in a home that holds old state. The refusal SHALL name the first old file, the versions the host reads, and the one command that moves the old state aside. Under outcome `OLDHOME-B` there is no refusal: the first such command moves the old state aside itself and writes a notice naming the backup directory on stderr.

#### Scenario: A home an older CLI wrote is refused
- **WHEN** a current host is asked to install `morphir-elm` into a home whose `catalog/extensions.json` is at `2.0.0-draft.2`
- **THEN** it refuses, names `catalog/extensions.json`, the version `2.0.0-draft.3` and the command that moves the old state aside, and changes no file

### Requirement: Old state moves to a named backup
Provisional on `Q-OLDHOME` (outcomes A and B). Under the state lock, a host SHALL move every lock and journal in `locks/extensions/`, then `catalog/extensions.json`, into `backups/extensions-<time>/`, `<time>` being the UTC time as `YYYYMMDDTHHMMSSZ`, each file keeping its path relative to the home. If a backup directory without a catalog exists, the host SHALL complete it, not start another. It SHALL NOT move the store, the repositories configuration or a lock file.

#### Scenario: The old state is moved aside
- **WHEN** the user runs that command at 2026-11-10T09:30:00Z in that home, which also holds `locks/extensions/morphir-elm.json` at `"1.0"`
- **THEN** `backups/extensions-20261110T093000Z/` holds `catalog/extensions.json` and `locks/extensions/morphir-elm.json`, the home holds neither, `config/extensions/repositories.json` is unchanged, and the next install writes a `2.0.0-draft.3` catalog

#### Scenario: An interrupted move is completed
- **WHEN** the command was interrupted after it moved the locks and before it moved the catalog, and the user runs it again
- **THEN** it moves the catalog into the same backup directory and starts no new one

### Requirement: Project configuration quotes a dotted id
A dotted id SHALL appear in project configuration as one quoted TOML key, such as `[extensions."org.finos.morphir.fsharp-frontend"]`. A configuration reader SHALL refuse an `extensions` entry whose key is not a valid id, naming the key and the rule it breaks. Diagnostics that print a configuration key for a dotted id SHALL print it quoted.

#### Scenario: A key that is not a valid id is refused
- **WHEN** a project configuration has `[extensions."Org.finos"]`
- **THEN** the reader refuses the entry and names the key and the rule `grammar`

#### Scenario: A diagnostic prints the quoted key
- **WHEN** a host reports a problem with the `command` of `org.finos.morphir.fsharp-frontend`
- **THEN** the message names `[extensions."org.finos.morphir.fsharp-frontend"].command`

#### Scenario: A single-segment key is unchanged
- **WHEN** a project configuration has `[extensions.morphir-elm]`
- **THEN** the reader reads it as before

### Requirement: An extension entry holds only its settings
The settings members of an `extensions` entry are `path`, `url`, `command`, `args`, `enabled` and `config`. A configuration reader SHALL refuse an entry that holds a member whose value is a table and whose name is not `config`. It SHALL ignore a member whose value is not a table and whose name is not a settings member.

#### Scenario: An extension's config table is read as settings
- **WHEN** a project configuration has `[extensions.acme.config]` with `x = 1`
- **THEN** the reader reads extension `acme` with the `config` table `{ x = 1 }`

### Requirement: A refused nested entry suggests the quoted key
For a refused nested table, the reader SHALL follow its tables down to the first table that holds a settings member or a value that is not a table. When each table on that chain has exactly one member, and the keys from the entry down that chain joined with `.` form a valid id, the refusal SHALL suggest that id as one quoted key. Otherwise it SHALL name the key path and suggest nothing.

#### Scenario: An unquoted dotted key is refused
- **WHEN** a project configuration has `[extensions.org.finos.morphir.fsharp-frontend]` with `command = "morphir-fsharp-frontend"`
- **THEN** the reader refuses the entry `org` and suggests `[extensions."org.finos.morphir.fsharp-frontend"]`

#### Scenario: A branching nested entry gets no suggestion
- **WHEN** a project configuration has `[extensions.acme.one]` with `command = "a"` and `[extensions.acme.two]` with `command = "b"`
- **THEN** the reader refuses the entry `acme`, names `extensions.acme.one`, and suggests no key

### Requirement: Hosts prove the rule against shared cases
The rules of this capability SHALL be published as language-neutral cases, except the lock primitive. Each case names an input and the expected outcome, and a refusal case also names the rule or the file it expects. Every host that reads extension ids SHALL run them and report the same outcome for every case. The lock primitive SHALL be proved by a test that runs two processes, because a data case cannot hold a lock.

#### Scenario: Two hosts agree on every case
- **WHEN** the .NET host and the MoonBit host run the shared extension id cases
- **THEN** both report the expected outcome for every case
