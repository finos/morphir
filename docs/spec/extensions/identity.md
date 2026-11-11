---
title: Extension identity
sidebar_position: 1
---

# Extension identity

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

These files, with the capability claim set, form one contract family, the extension state family, at one version: `0.1.0-preview.1` (maintainer, Decision 15, 10 November 2026). Each JSON document carries the version in a required `$schema` member whose value is that file's schema URL, `https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/<file>.schema.json`. No document has a `schemaVersion` member.

| File | Path | Schema file (`<file>.schema.json`) | Unknown members |
| --- | --- | --- | --- |
| Release descriptor | `release.json` in a release | `release.schema.json` | ignored unless named in `critical` |
| Index record | each line of `extensions/<id>.jsonl` in a repository | `index-record.schema.json` | ignored unless named in `critical` |
| Installed catalog | `catalog/extensions.json` | `catalog.schema.json` | ignored unless named in `critical` |
| Extension lock | `locks/extensions/<id>.json` | `lock.schema.json` | refused |
| Transaction journal | `locks/extensions/<id>.json.transaction` | `journal.schema.json` | refused |
| Repositories configuration | `config/extensions/repositories.json` | `repositories.schema.json` | refused |
| Capability claim set | inside a descriptor, record or catalog entry, or alone as `describe` returns it | `claims.schema.json` | as its enclosing document, or ignored unless named in `critical` when alone |
| State lock | `locks/extensions.state.lock` | none, no content | not applicable |
| Repositories lock | `locks/extensions.repositories.lock` | none, no content | not applicable |
| Publish lock | `.publish.lock` in a local repository | none, no content | not applicable |

A document's current schema URL is the URL of its file at `0.1.0-preview.1`. A JSONL history has no header, so each line carries its own `$schema`.
Paths in the home are relative to the home root, and paths in a repository are relative to the repository root.

The [distribution contract](../../design/draft/extensions/distribution-and-acquisition.md#shared-extension-state-contract) is the authority for the member tables of these shared files. The [published schemas](https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/release.schema.json) encode their structural constraints. Packages are part of this first family version, as established by the [approval-time audit](./publication-audit.md).

A host can find a home in a state it cannot use: files without the current schema URL, such as those an older host wrote with a `schemaVersion` member, more than one journal, or a journal whose saved documents fail their checks. This page calls all of these old state. The maintainer decided what a host does with it on 10 November 2026 (Decision 10, recorded on finos/morphir#1146): it moves the old state to a marked backup, asking first; `--yes` skips the question; `morphir doctor --fix` makes the same move by hand. The maintainer confirmed four readings of it the same day (Decision 11): the refusal without a terminal or on a decline, `morphir doctor` reporting only, and `morphir doctor --fix` asking first.

The device list follows [Microsoft Naming Files, Paths, and Namespaces](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file#naming-conventions), checked 11 November 2026. It names COM1 through COM9 and LPT1 through LPT9, without COM0 or LPT0. Superscript forms fail the ASCII grammar first. The .NET host reserves every id starting with `morphir.` for its built-ins and does not reserve `org.finos.morphir.*`. This host refusal grants no publisher trust and creates no publisher-prefix registry.

[Language-neutral cases](./identity-cases.json) pin outcomes. Their operations describe inputs and expected results for a host runner. TypeScript checks only their integrity and schema examples.

## Requirements

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

### Requirement: A reader refuses a catalog out of order
A reader SHALL refuse a catalog whose `extensions` entries are not in ascending byte order of `extensionId`, or that names one id in two entries, and SHALL name the file and the first entry out of place.

#### Scenario: A catalog with an id twice
- **WHEN** a host reads a current catalog whose entries are `morphir-elm`, `morphir-elm`
- **THEN** it refuses the catalog and names its second entry

### Requirement: State changes are made under the state lock
A host SHALL take the state lock `locks/extensions.state.lock` before it detects old state, replays a journal or reads, writes or removes the catalog, a lock or a journal, and SHALL hold it until the last of those writes and removals is complete. A host SHALL take the repositories lock `locks/extensions.repositories.lock` in the same way around every read-modify-write of `config/extensions/repositories.json`. A host SHALL NOT hold both lock files at once.

#### Scenario: Two hosts exclude each other
- **WHEN** one process holds the state lock of a home and a process of another host implementation starts an install into the same home
- **THEN** the second process reads and writes no catalog, lock or journal until the first releases the state lock

#### Scenario: The two locks are never held together
- **WHEN** a host installs an extension from a configured repository
- **THEN** it reads the repositories configuration under the repositories lock, releases it, and only then takes the state lock

### Requirement: The lock primitive is a whole-file exclusive operating-system lock
A host SHALL take each lock file with one primitive: on Unix, `flock` with `LOCK_EX` and without `LOCK_NB` on a descriptor open on the file; on Windows, `LockFileEx` with `LOCKFILE_EXCLUSIVE_LOCK` and without `LOCKFILE_FAIL_IMMEDIATELY` from offset 0 over a length of `0xFFFFFFFF` low and `0xFFFFFFFF` high. A host SHALL create a lock file that is absent, SHALL NOT write content to it, and SHALL NOT remove it.

#### Scenario: A record lock does not count
- **WHEN** a host on Linux takes the state lock
- **THEN** it calls `flock` with `LOCK_EX`, so that another host's `flock` on the same file waits, and it does not rely on an `fcntl` record lock

### Requirement: A lock file is opened so that a second host waits rather than fails
On Unix a host SHALL open a lock file with `open` and `O_RDWR`, `O_CREAT` and `O_CLOEXEC`, mode `0644`, and SHALL take no lock on it other than the one this capability names. On Windows a host SHALL open it with read and write access and with `FILE_SHARE_READ`, `FILE_SHARE_WRITE` and `FILE_SHARE_DELETE`. A host MAY stop waiting after a time it reports, and SHALL NOT go on without the lock.

#### Scenario: A .NET host waits for another host's lock
- **WHEN** another host holds the state lock and the .NET host starts an install on Linux
- **THEN** the .NET host's open of `locks/extensions.state.lock` succeeds and its `flock` call waits, instead of the open failing because of a lock that .NET takes when it opens a file

### Requirement: A home on a network file system is not supported
A home on a network file system SHALL be outside this contract, because the lock primitive does not keep its guarantees there. A host that can tell that the home is on a network file system SHALL refuse every command that reads or writes extension state, naming the home and saying it is not supported. A host is not required to detect it.

#### Scenario: A host that can tell refuses
- **WHEN** a host on Linux finds through `statfs` that `MORPHIR_HOME` is on NFS
- **THEN** it refuses the install, names the home and says a home on a network file system is not supported

### Requirement: Shared documents are I-JSON compared by parsed values
Every shared JSON document SHALL be UTF-8 without a byte order mark and SHALL be I-JSON (RFC 7493). A member name SHALL NOT repeat in an object. A number SHALL be an integer written without a fraction or an exponent. A reader SHALL refuse a document that breaks these rules. Strings SHALL be compared code point by code point without normalization, and array order is significant.

#### Scenario: Numbers in another form
- **WHEN** a host reads a journal whose `nextLock` holds `123.0`, or a lock whose member name appears twice
- **THEN** it refuses the document and names the file

### Requirement: Absent and null are different
A member that is absent SHALL differ from a member whose value is `null`. A reader SHALL refuse `null` for a member unless this capability or the page that defines the member allows it. Two installers SHALL be treated as conforming when their documents are equal as parsed values; their bytes, member order, spacing and line endings need not be equal.

#### Scenario: Different spacing, same document
- **WHEN** two hosts write the same catalog entries with different indentation and member order
- **THEN** each host reads the other's catalog as the same catalog

### Requirement: Documents that carry a claim set ignore unknown members unless critical
A reader of a release descriptor, an index record or an installed catalog SHALL ignore a member it does not understand unless the document's top-level `critical` list names its path, and SHALL refuse a document whose `critical` list names a path it does not understand. A path names an array element's member through the array's name, as in `extensions.note` for a catalog entry's `note`.

#### Scenario: An unknown member in an open document
- **WHEN** a host reads a current catalog whose entry holds an optional member `note` that it does not understand, and another catalog whose top-level `critical` list names `extensions.note`
- **THEN** it reads the first catalog and ignores `note`, and refuses the second

### Requirement: Locks, journals and the repositories configuration refuse unknown members
A reader of an extension lock, a transaction journal or the repositories configuration SHALL refuse a document that holds a member the contract does not define for it, and SHALL name the file and the member.

#### Scenario: An unknown member in a closed document
- **WHEN** a host reads a current extension lock that holds a member `installedBy`
- **THEN** it refuses the lock and names the file and the member

### Requirement: Writers spell repository paths as ordinary absolute paths
A writer SHALL write `endpoint.path` in the repositories configuration and `index.identity` in a lock as the path that `realpath` (Unix) or `GetFinalPathNameByHandleW` with `FILE_NAME_NORMALIZED` and `VOLUME_NAME_DOS` (Windows) reports for the open repository root. It SHALL NOT write the verbatim prefix `\\?\`, SHALL write `\\?\UNC\server\share\…` as `\\server\share\…`, SHALL write a drive letter in uppercase, and SHALL write no trailing separator except at a volume root such as `D:\`.

#### Scenario: A writer drops the verbatim prefix
- **WHEN** a host on Windows adds the local repository `C:\ext-repo` and the operating system reports its final path as `\\?\C:\ext-repo`
- **THEN** the host writes `C:\ext-repo` as `endpoint.path`

#### Scenario: A volume root keeps its separator
- **WHEN** a host on Windows adds a repository at the root of drive `D:` and the operating system reports `\\?\D:\`
- **THEN** the host writes `D:\`

### Requirement: Readers refuse a verbatim path
A reader SHALL refuse a repositories configuration or lock whose repository path carries the verbatim prefix `\\?\`, naming the file and the path. A reader SHALL compare repository paths by their bytes. The reader rule of the earlier revision, which read a prefixed path as the plain one, existed only for repositories files that the Rust CLI wrote at version 1; those are now old state.

#### Scenario: A verbatim path is refused
- **WHEN** a current repositories configuration names a repository at `\\?\C:\ext-repo`
- **THEN** the reader refuses the file and names the path

#### Scenario: Paths compare by bytes
- **WHEN** a repositories configuration names `C:\ext-repo` and a lock's `index.identity` is `C:\ext-repo`
- **THEN** a host treats both as the same repository

### Requirement: Each document of the family has a published schema
Each file of the extension state family SHALL have a JSON Schema published at its schema URL, from `website/static/schemas/extensions/0.1.0-preview.1/<file>.schema.json`. A document SHALL be valid against that schema. A reader MAY validate against the schema; the requirements of this capability decide every outcome.

#### Scenario: A descriptor validates against its schema
- **WHEN** an editor opens a current `release.json`
- **THEN** it can fetch `https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/release.schema.json` from the document's `$schema` and validate the document against it

### Requirement: A capability claim set carries a schema URL only when it stands alone
A claim set inside a descriptor, record or catalog entry SHALL carry no version or `$schema` of its own; its enclosing document's schema covers it. A claim set that stands alone, as `morphir.extension.describe` returns it, SHALL carry the `$schema` `…/0.1.0-preview.1/claims.schema.json` in place of `claimsVersion`.

#### Scenario: Embedded and standalone claims
- **WHEN** a host reads a current descriptor whose artifact holds claims, and a guest's `describe` result
- **THEN** the embedded claims have no `$schema` or `claimsVersion`, and the `describe` result's `$schema` is the claims schema URL

### Requirement: Shared files are replaced through temporary files that readers ignore
A writer SHALL replace a shared file by writing a temporary file in the same directory, flushing it, and renaming it over the target. A temporary file's name SHALL start with `.stage-`. A reader that lists `locks/extensions/`, `catalog/` or a repository's `extensions/` SHALL ignore every entry whose name starts with `.`, and every entry that is not a regular file. No name derived from an id starts with `.`.

#### Scenario: A temporary file is not a journal
- **WHEN** a host takes the state lock and finds `locks/extensions/.stage-3f2a` and `locks/extensions/morphir-elm.json.transaction`
- **THEN** recovery considers only `morphir-elm.json.transaction` and leaves `.stage-3f2a` in place

### Requirement: The transaction journal has a fixed version and encoding
A host SHALL journal each change to an extension's lock and the catalog in `locks/extensions/<id>.json.transaction` before it writes either file. The journal SHALL have exactly the members `$schema`, `nextLock` and `nextCatalog`. `$schema` SHALL be the journal's current schema URL. `nextLock` and `nextCatalog` SHALL each be present, and each SHALL be `null`, meaning the file is to be absent, or an array of integers from 0 to 255, written in decimal, holding the file's exact bytes.

#### Scenario: A journal of an install
- **WHEN** a host installs `morphir-elm` and has written its journal but not yet the lock
- **THEN** `locks/extensions/morphir-elm.json.transaction` has the `$schema` `https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/journal.schema.json` and holds the new lock's and the new catalog's bytes as arrays of integers

### Requirement: One journal exists at a time
A host SHALL NOT write a journal while another journal exists in `locks/extensions/`. When a host cannot remove a journal after its change is committed, the command SHALL fail and report the journal, and the next state command SHALL recover it before anything else.

#### Scenario: A deferred cleanup is finished first
- **WHEN** a host committed an install of `morphir-elm` but could not remove `morphir-elm.json.transaction`, and a second install of `acme.tools` starts
- **THEN** the second install recovers and removes the first journal before it writes its own

### Requirement: Old state is detected before recovery
Under the state lock, before it recovers any journal, a host SHALL check for old state: a catalog, extension lock, journal or repositories configuration whose `$schema` is missing or is not its current schema URL, more than one journal, or a journal that fails the checks of the next requirement. It SHALL read only each file's `$schema` and the journals to do so. Only when the home holds no old state SHALL it recover a journal.

#### Scenario: A home the Rust CLI left mid-install
- **WHEN** a current host takes the state lock in a home with a catalog an older CLI wrote, with `schemaVersion` `2.0.0-draft.2` and no `$schema`, and `locks/extensions/morphir-elm.json.transaction` with `schemaVersion` integer `1`
- **THEN** it reports old state and offers to move it aside, and does not report a journal refusal first

#### Scenario: Two journals are old state
- **WHEN** a host takes the state lock and finds `morphir-elm.json.transaction` and `acme.tools.json.transaction`
- **THEN** it writes nothing from either, and reports both as old state

### Requirement: Recovery checks a journal before it writes
A journal passes its checks when its `$schema` is the journal's current schema URL and its saved lock and saved catalog are valid current documents, each validated in full as that document's reader validates it, including `$schema`, ids, order and critical members. Recovery SHALL write the lock, then the catalog, then remove the journal.

#### Scenario: An interrupted install is completed
- **WHEN** a host takes the state lock and finds one current journal for `morphir-elm` whose saved lock and catalog pass their checks
- **THEN** it writes `locks/extensions/morphir-elm.json` and `catalog/extensions.json` with the saved bytes and removes the journal

#### Scenario: A journal at an earlier version is old state
- **WHEN** a host takes the state lock and finds a journal with no `$schema` and a `schemaVersion` of integer `1`
- **THEN** it writes nothing from the journal and reports it as old state

#### Scenario: A journal that would restore an earlier document is old state
- **WHEN** a host finds a current journal whose `nextCatalog` holds the bytes of a catalog with `schemaVersion` `2.0.0-draft.2` and no `$schema`
- **THEN** it writes neither the lock nor the catalog and reports the journal as old state

### Requirement: Every document of the family carries its current schema URL
A writer SHALL write every document of the extension state family with a `$schema` member, written first, whose value is that file's schema URL at `0.1.0-preview.1`, whatever the form of the ids it names, and SHALL write no `schemaVersion` member. Each JSONL history line SHALL carry its own `$schema`. The family version differs from the earlier per-file versions in the id grammar and in carrying the version by URL.

#### Scenario: A single-segment release is written at the family version
- **WHEN** a publisher authors a release with the id `morphir-elm`
- **THEN** its descriptor's `$schema` is `https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/release.schema.json`, and it has no `schemaVersion`

#### Scenario: A single-segment index record and lock are written at the family version
- **WHEN** a publisher adds a `morphir-elm` release to a repository, and a host installs it
- **THEN** the new line of `extensions/morphir-elm.jsonl` has the `$schema` `…/0.1.0-preview.1/index-record.schema.json`, and `locks/extensions/morphir-elm.json` has the `$schema` `…/0.1.0-preview.1/lock.schema.json`

#### Scenario: An earlier document is refused before any id is read
- **WHEN** a reader reads a descriptor with `schemaVersion` `2.0.0-draft.2` or a lock with `schemaVersion` `"1.0"`, either naming `org.finos.morphir.fsharp-frontend`
- **THEN** it refuses the document as an unsupported extension schema, as it refuses the same document naming `morphir-elm`

### Requirement: A reader reads only the current schema URLs
A reader SHALL accept a document of the family only when its `$schema` is that file's current schema URL, compared as exact text. It SHALL NOT read any other document, including one with a `schemaVersion` member and no `$schema`, as earlier hosts wrote. No conversion between versions is part of this contract. A reader that meets another document SHALL refuse it, naming the file and the URL it reads.

#### Scenario: Another preview is refused
- **WHEN** a current host reads a catalog whose `$schema` is `https://morphir.finos.org/schemas/extensions/0.1.0-preview.2/catalog.schema.json`
- **THEN** it refuses the catalog and names the URL it reads, `…/0.1.0-preview.1/catalog.schema.json`

#### Scenario: A current host meets an earlier descriptor
- **WHEN** a current host reads a release whose descriptor has `schemaVersion` `2.0.0-draft.2` and no `$schema`
- **THEN** it refuses the release as an unsupported extension schema, names `release.json` and the URL `https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/release.schema.json`, and installs nothing

### Requirement: A repository history is read whole and holds one version
A reader SHALL read a history `extensions/<id>.jsonl` whole. Lines are separated by LF and numbered from 1; a line that holds only JSON whitespace, a CR included, is skipped but still counted. Each line SHALL carry its own `$schema`. When any line is not an index record whose `$schema` is the index record's current schema URL, the reader SHALL refuse the whole file, name the file and the number of the first such line, and select no release from it. A history with no record SHALL be refused.

#### Scenario: A history with earlier lines is refused
- **WHEN** a reader reads `extensions/morphir-elm.jsonl` whose lines 1 and 2 are records with `schemaVersion` `2.0.0-draft.2` and whose line 3 is a current record
- **THEN** it refuses the file, names it and line 1, and resolves no `morphir-elm` release from it

#### Scenario: CRLF lines and an empty history
- **WHEN** a reader reads one history whose two current records end in CR LF, and another that is empty or holds only blank lines
- **THEN** it reads the first, and refuses the second as a history with no record

### Requirement: A publisher does not append to a history at another version
A publisher SHALL NOT append a current record to a history that holds a line without the current schema URL. It SHALL refuse the publication, name the file and the first such line, and leave the file unchanged.

#### Scenario: A publisher does not create a mixed history
- **WHEN** a publisher adds a current release of `morphir-elm` to a repository whose `extensions/morphir-elm.jsonl` holds lines with `schemaVersion` `2.0.0-draft.2`
- **THEN** it refuses the publication, names the file and its first earlier line, and leaves the file unchanged

### Requirement: A publisher holds the repository's publish lock
A publisher to a local repository SHALL hold an exclusive lock on `.publish.lock` at the repository root, with the primitive and opening rules of the state lock, from before it reads a history until after it has written it. It SHALL create the file if absent and SHALL NOT write content to it.

#### Scenario: Two publishers to one repository
- **WHEN** two publishers add `morphir-elm` 0.8.0 and 0.8.1 to the same local repository at the same time
- **THEN** one waits for the other's publish lock, and the history ends with both records, each written once

### Requirement: A host does not read, replay or convert old state
A host SHALL NOT read, replay or convert old state; it only moves it aside (maintainer, Decision 10, 10 November 2026). Converting old state in place contradicts the decision that transient drafts are not converted, so this change specifies no conversion. When any file is old state, every extension's state in the home is old state: a current catalog beside one old extension lock is moved aside too.

#### Scenario: Old state is found by version
- **WHEN** a current host takes the state lock in a home whose catalog is current and whose `locks/extensions/morphir-elm.json` has `schemaVersion` `"1.0"` and no `$schema`
- **THEN** it treats the home as holding old state, naming `locks/extensions/morphir-elm.json`

### Requirement: A command that meets old state offers to move it aside
When a command that needs extension state finds old state, the host SHALL show what the move would take, ask the user to accept moving it to a backup, and on acceptance run the move of `morphir doctor --fix` and go on with the command. With `--yes`, the host SHALL make the move without asking. The host SHALL write the question and the notice naming the backup directory on stderr.

#### Scenario: Accepted at the prompt
- **WHEN** a user at a terminal runs an install of `morphir-elm` in a home whose catalog an older CLI wrote at `schemaVersion` `2.0.0-draft.2`, and accepts the prompt
- **THEN** the host moves the old state to `backups/extensions-<time>/`, writes the notice on stderr, and installs `morphir-elm` into a new current catalog

#### Scenario: Skipped with --yes
- **WHEN** the same install runs with `--yes`
- **THEN** the host makes the same move without asking and installs `morphir-elm`

### Requirement: A declined or unanswerable prompt changes nothing
Decision 11, readings 1 and 2. When the user declines the prompt, or when standard input is not a terminal and `--yes` is not given, the host SHALL refuse the command and change nothing. The refusal SHALL name the first old file, `morphir doctor --fix` and `--yes`.

#### Scenario: Declined
- **WHEN** the user declines the prompt
- **THEN** the command fails, no file in the home changes, and the message names `catalog/extensions.json`, `morphir doctor --fix` and `--yes`

#### Scenario: No terminal and no --yes
- **WHEN** an install runs in a script whose standard input is not a terminal, without `--yes`, in a home with old state
- **THEN** it asks nothing, fails, changes nothing, and names the same file, `morphir doctor --fix` and `--yes`

### Requirement: morphir doctor reports old state
`morphir doctor` SHALL check the home for old state and for a backup without its completion marker. Decision 11, reading 3: without `--fix` it SHALL report each finding and the files `--fix` would move, and change nothing. It SHALL write its result on stdout and its messages on stderr, and exit 0 when it finds nothing to fix, 1 when it finds something, and 2 when it does not run, such as on an unknown option.

#### Scenario: doctor reports only
- **WHEN** a user runs `morphir doctor` in a home whose catalog an older CLI wrote at `schemaVersion` `2.0.0-draft.2`
- **THEN** it reports old state, lists the catalog and each extension lock and journal that `--fix` would move, exits 1, and changes no file

### Requirement: morphir doctor --fix makes the move
`morphir doctor --fix` SHALL make the move of "Old state moves to a named backup" and complete an unmarked backup. Decision 11, reading 4: it SHALL first show what it will move and ask, unless `--yes` is given, and a declined or unanswerable prompt SHALL change nothing. It SHALL exit 0 when nothing is left to fix, and 1 otherwise.

#### Scenario: doctor --fix moves
- **WHEN** a user runs `morphir doctor --fix --yes` in a home with old state
- **THEN** it moves the old state to a marked backup, reports the backup directory, and exits 0

#### Scenario: A second run finds nothing to fix
- **WHEN** `morphir doctor --fix` runs again in that home, or `morphir doctor` runs there
- **THEN** it finds nothing to fix, changes nothing, and exits 0

### Requirement: The automatic path and doctor --fix make the same move
The move a command makes on acceptance and the move `morphir doctor --fix` makes SHALL be one operation: the same files moved in the same order, the same backup layout and the same completion marker. A host SHALL implement them once.

#### Scenario: The same backup either way
- **WHEN** two copies of one home with old state are repaired, one by an install accepted at the prompt and one by `morphir doctor --fix --yes`
- **THEN** both backup directories hold the same files at the same paths, each with `.complete`, and both homes hold no old state

### Requirement: The host asks without holding the state lock
A host SHALL detect old state under the state lock, release the lock before it asks, and take it again after acceptance. It SHALL then detect old state again. When the old state differs from what it showed, it SHALL show it and ask again, or with `--yes` move what it now finds. It SHALL make the move and then the command's own state change in that one hold.

#### Scenario: The command continues against the empty state
- **WHEN** an uninstall of `morphir-elm` is accepted at the prompt in a home whose old catalog listed `morphir-elm`
- **THEN** the host moves the old state, and the uninstall then finds `morphir-elm` not installed in the empty state and reports that

### Requirement: Old state moves to a named backup
Under the state lock, a host SHALL move every journal and extension lock in `locks/extensions/`, then `catalog/extensions.json` if present, into `backups/extensions-<time>/` (UTC, as `YYYYMMDDTHHMMSSZ`), each keeping its path relative to the home, then write an empty `.complete` there. It SHALL also move `config/extensions/repositories.json` when that file is old state, and SHALL NOT move the store, a current repositories configuration or either lock file.

#### Scenario: The old state is moved aside
- **WHEN** the move runs at 2026-11-10T09:30:00Z in a home an older CLI wrote: its catalog at `schemaVersion` `2.0.0-draft.2`, `locks/extensions/morphir-elm.json` at `"1.0"`, and `config/extensions/repositories.json` at `schemaVersion` `1`
- **THEN** `backups/extensions-20261110T093000Z/` holds those three files and `.complete`, the home holds none of them, and the next install writes a current catalog

#### Scenario: Old state without a catalog
- **WHEN** the home holds `locks/extensions/morphir-elm.json` at `"1.0"`, a current repositories configuration and no catalog, and the move runs
- **THEN** the backup directory holds that lock and `.complete`, and no catalog, and the current repositories configuration stays in the home

### Requirement: Only a backup without its completion marker is completed
A backup directory `backups/extensions-<time>/` is complete when it holds `.complete`. When exactly one lacks it, the move SHALL put any old state into it, then write `.complete`, instead of starting another. With no old state left, any state command except `morphir doctor` without `--fix` SHALL only write `.complete`, without asking. When more than one lacks it, a file to move exists at its target, or a new directory's name exists, the host SHALL refuse and name them.

#### Scenario: An interrupted move is completed
- **WHEN** the move was interrupted after it moved the extension locks and before it moved the catalog, and it runs again
- **THEN** it moves the catalog into the same backup directory, writes `.complete`, and starts no new one

#### Scenario: Interrupted before the marker
- **WHEN** the move had moved every file but stopped before writing `.complete`, and any state command other than `morphir doctor` without `--fix` runs
- **THEN** the host writes `.complete` in that directory, without asking, and goes on, since no old state is left

#### Scenario: A completed backup is never reused
- **WHEN** a complete backup holds `locks/extensions/morphir-elm.json`, the older CLI later writes old state again, and the move runs
- **THEN** it creates a new backup directory, and the complete one is unchanged

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
The settings members of an `extensions` entry and their types are `path`, `url` and `command` (strings), `args` (an array of strings), `enabled` (a boolean) and `config` (a table). A configuration reader SHALL refuse a settings member of another type, naming it and its type, except a table under a settings name, which is a nested entry. It SHALL refuse any other member whose value is a table or an array of tables, and SHALL ignore any other member.

#### Scenario: An extension's config table is read as settings
- **WHEN** a project configuration has `[extensions.acme.config]` with `x = 1`
- **THEN** the reader reads extension `acme` with the `config` table `{ x = 1 }`

#### Scenario: Settings of the wrong type
- **WHEN** a project configuration has `[extensions.acme]` with `config = 1`, and another has `[[extensions.acme.args]]`, and a third has `[[extensions.acme.x]]`
- **THEN** the reader refuses `config` as not a table, `args` as not an array of strings, and `x` as an array of tables

### Requirement: A refused nested entry suggests the quoted key
A nested entry is a member of an entry whose value is a table and whose name is not `config`. The reader SHALL follow the nested tables down to the first table that holds a settings member of its settings type. When each table above that one has exactly one member, and the keys from the entry down to it joined with `.` form a valid id, the refusal SHALL suggest that id as one quoted key. Otherwise it SHALL name the key path and suggest nothing.

#### Scenario: A dotted id whose last segment is a settings name
- **WHEN** a project configuration has `[extensions.acme.path]` with `command = "x"`
- **THEN** the reader refuses the entry `acme` and suggests `[extensions."acme.path"]`, because `path` there is a table, not a string

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
