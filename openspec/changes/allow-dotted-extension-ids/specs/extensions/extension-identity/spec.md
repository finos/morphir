# Spec Delta

## Purpose

Defines the identity of a Morphir extension: the grammar of its id, how ids are compared, what an id does and does not mean, the file and key names a host derives from it, and the contract versions that carry an id with more than one segment. Every host, repository and toolchain contract that names an extension follows it.

An id is one or more segments joined by `.`. `morphir-elm` has one segment. `org.finos.morphir.fsharp-frontend` has four, in reverse-DNS style. Both are valid, both are compared byte for byte, and neither says anything about who published the extension.

| Id | Valid | Why |
| --- | --- | --- |
| `morphir-elm` | yes | one segment |
| `org.finos.morphir.fsharp-frontend` | yes | four segments |
| `morphir.csharp` | yes | two segments |
| `a..b` | no | empty segment |
| `Org.finos` | no | uppercase |
| `con.example` | no | first segment is a Windows device name |

## ADDED Requirements

### Requirement: An extension id is a dotted portable token
An extension id SHALL be one or more segments joined by `.`. Each segment SHALL start with a lowercase ASCII letter, contain only lowercase ASCII letters, digits and `-`, and end with a lowercase ASCII letter or digit. An id SHALL have at most 238 characters in total, counting the dots. A segment has no length limit of its own.

#### Scenario: Valid ids
- **WHEN** a reader reads the ids `morphir-elm`, `a`, `morphir.csharp`, `acme.tools.lint-2` and `org.finos.morphir.fsharp-frontend`
- **THEN** each one is accepted as an extension id

#### Scenario: Invalid ids
- **WHEN** a reader reads the ids `""`, `.`, `..`, `a..b`, `.a`, `a.`, `A`, `a.B`, `1a`, `a.1b`, `a-`, `a.b-`, `a_b`, `a b` and `a/b`
- **THEN** each one is refused, and the refusal names the id and the rule it breaks

#### Scenario: Length boundary
- **WHEN** a reader reads a valid id of exactly 238 characters and the same id with one more character
- **THEN** the first is accepted and the second is refused

### Requirement: The first segment of an id is not a Windows device name
An extension id SHALL be refused when its first segment is `con`, `prn`, `aux`, `nul`, or `com` or `lpt` followed by a single digit from `1` to `9`. Later segments are not restricted by this rule.

#### Scenario: Device names in the first segment
- **WHEN** a reader reads the ids `con`, `nul.tools`, `com1.lint` and `lpt9`
- **THEN** each one is refused as a Windows device name

#### Scenario: Device names in later segments
- **WHEN** a reader reads the ids `acme.con`, `acme.nul.tools` and `console.tools`
- **THEN** each one is accepted

### Requirement: Every existing single-segment id keeps its meaning
Every id that is valid under the single-token rule of descriptor `2.0.0-draft.2` SHALL be valid under this rule and SHALL denote the same extension. A document that is valid today SHALL stay valid and SHALL read the same.

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
- **THEN** its authentication is still `local-developer` and its claim check is still decided by the probe
- **AND** no host treats it as published by FINOS because of its id

### Requirement: Names derived from an id are the id with a fixed suffix
Wherever a host or repository derives a file name or a key from an extension id, it SHALL use the whole id followed by a fixed suffix, such as `<id>.jsonl`, `<id>.json` or `<id>.json.transaction`. Two different ids SHALL never derive the same name. The content-addressed artifact store SHALL NOT use the id in its paths.

#### Scenario: Derived names do not collide
- **WHEN** a host installs `acme.tools` and `acme-tools` and records their locks
- **THEN** it writes the two locks as `acme.tools.json` and `acme-tools.json`, in their partitions' lock directories, and no name it derives for one equals a name it derives for the other on any first-delivery platform, including case-insensitive file systems

#### Scenario: A repository history is found by its full id
- **WHEN** a repository index holds `extensions-dotted/org.finos.morphir.fsharp-frontend.jsonl`
- **THEN** a reader takes the id `org.finos.morphir.fsharp-frontend` from the file name and refuses the file if its records name another id

### Requirement: A home keeps dotted extensions apart from the state older hosts read
A Morphir home SHALL record a dotted extension only in the dotted partition: the catalog `catalog/extensions-dotted.json` and the lock directory `locks/extensions-dotted/`, which holds its locks and their transaction journals. The catalog `catalog/extensions.json` and the directory `locks/extensions/` SHALL hold only single-segment ids.

#### Scenario: A dotted install leaves the existing files alone
- **WHEN** a new host installs `org.finos.morphir.fsharp-frontend` into a home that holds `morphir-elm`
- **THEN** it writes `catalog/extensions-dotted.json` and `locks/extensions-dotted/org.finos.morphir.fsharp-frontend.json`
- **AND** `catalog/extensions.json` and every file in `locks/extensions/` keep their bytes

#### Scenario: A host lists both partitions
- **WHEN** a new host lists the installed extensions of that home
- **THEN** it lists `morphir-elm` and `org.finos.morphir.fsharp-frontend` together, in id order

### Requirement: Both home partitions share one state lock
A host SHALL change either partition only while holding the one state lock `locks/extensions.state.lock`. One install, update or removal SHALL change exactly one partition, and a host SHALL recover each partition's journals into that partition's own catalog.

#### Scenario: Concurrent hosts
- **WHEN** an older host updates `morphir-elm` while a new host installs `org.finos.morphir.fsharp-frontend` in the same home
- **THEN** one waits for the other's state lock, and each partition ends in the state its own transaction wrote

### Requirement: An older host keeps working on a home that holds dotted extensions
A host that predates this rule SHALL be able to install, update, list, remove and run single-segment extensions in a home that also holds dotted extensions, exactly as in a home that does not. No file such a host reads or recovers SHALL name a dotted id.

#### Scenario: Downgrade after a dotted install
- **WHEN** a home holds `morphir-elm` and `org.finos.morphir.fsharp-frontend`, and a host released before this change runs `extension update morphir-elm`, `extension list` and a compile with `morphir-elm`
- **THEN** each succeeds as it would without the dotted extension, and the list does not show the dotted extension

#### Scenario: An interrupted dotted install
- **WHEN** a new host is interrupted while installing `org.finos.morphir.fsharp-frontend` and an older host then runs any extension command in that home
- **THEN** the older host finds no journal of that install in `locks/extensions/` and writes nothing to `catalog/extensions.json` on its behalf
- **AND** the next new host to take the state lock completes or rolls back the install from `locks/extensions-dotted/`

### Requirement: A new host refuses state in the wrong partition
A new host SHALL refuse a dotted id found in `catalog/extensions.json` or `locks/extensions/`, and a single-segment id found in `catalog/extensions-dotted.json` or `locks/extensions-dotted/`. The refusal SHALL name the file. It SHALL NOT stop the other partition from being read and used.

#### Scenario: A dotted id in the existing catalog
- **WHEN** `catalog/extensions.json` holds an entry for `org.finos.morphir.fsharp-frontend`
- **THEN** a new host refuses that catalog and names it
- **AND** it still lists and runs the extensions recorded in the dotted partition

### Requirement: A repository index keeps dotted histories apart
A repository index SHALL keep the history of a dotted id in `extensions-dotted/<id>.jsonl`, and SHALL keep only single-segment ids in `extensions/`. A reader resolves an id from the directory its form names. A search or verification by a new reader SHALL read both directories.

#### Scenario: An older client searches a mixed repository
- **WHEN** a repository holds `extensions/morphir-elm.jsonl` and `extensions-dotted/org.finos.morphir.fsharp-frontend.jsonl`, and a client released before this change runs `extension search elm` and `extension repository verify`
- **THEN** both succeed, and they see only `morphir-elm`

#### Scenario: A new client sees both
- **WHEN** a new client runs `extension search fsharp` against that repository
- **THEN** the results include `org.finos.morphir.fsharp-frontend`

### Requirement: A dotted id uses the drafts that introduce it
A writer SHALL write a release descriptor, repository index record or dotted installed catalog that names a dotted id at `2.0.0-draft.3`, and a dotted extension's lock at `2.0.0-draft.1`. For a single-segment id it SHALL keep writing the version it writes today, until the oldest host it targets reads the new draft. A reader of the new drafts SHALL also read every version it read before.

#### Scenario: A dotted release is written at the new draft
- **WHEN** a publisher authors a release with the id `org.finos.morphir.fsharp-frontend`
- **THEN** its descriptor has `schemaVersion` `2.0.0-draft.3`

#### Scenario: Existing documents stay byte-identical
- **WHEN** a new host installs `morphir-elm` from a `2.0.0-draft.2` descriptor into a home that also holds a dotted extension
- **THEN** the index record, `catalog/extensions.json` and lock it writes have the versions and bytes an earlier host writes in the same home without the dotted extension

#### Scenario: A new reader reads the earlier drafts
- **WHEN** a new host reads `2.0.0-draft.1` and `2.0.0-draft.2` descriptors and a `1.0` lock
- **THEN** it reads them as before

### Requirement: An earlier reader refuses a dotted descriptor by version
A release descriptor that names a dotted id SHALL be one that a reader of only the earlier drafts refuses with its unsupported-version error, before it reads the id. Together with the partitions, this means a dotted id never reaches a reader that does not understand it.

#### Scenario: An old host is handed a dotted bundle
- **WHEN** a host that reads only `2.0.0-draft.1` and `2.0.0-draft.2` reads a `2.0.0-draft.3` descriptor, for example from a bundle directory
- **THEN** it refuses the descriptor as an unsupported extension schema version and changes nothing

### Requirement: Project configuration quotes a dotted id
A dotted id SHALL appear in project configuration as one quoted TOML key, such as `[extensions."org.finos.morphir.fsharp-frontend"]`. A configuration reader SHALL refuse an `extensions` entry whose key is not a valid id or whose value nests further tables in place of the extension's settings. The refusal SHALL show the quoted spelling. Diagnostics that print a configuration key for a dotted id SHALL print it quoted.

#### Scenario: An unquoted dotted key is refused
- **WHEN** a project configuration has `[extensions.org.finos.morphir.fsharp-frontend]`
- **THEN** the reader refuses it and suggests `[extensions."org.finos.morphir.fsharp-frontend"]`

#### Scenario: A single-segment key is unchanged
- **WHEN** a project configuration has `[extensions.morphir-elm]`
- **THEN** the reader reads it as before

### Requirement: Hosts prove the rule against shared cases
The id grammar, the device-name rule, the length boundary, exact comparison, derived names, the home and repository partitions, the version rule and configuration quoting SHALL be published as language-neutral cases. Each case names an input and the expected acceptance or refusal. Every host that reads extension ids SHALL run them and report the same outcome for every case.

#### Scenario: Two hosts agree on every case
- **WHEN** the Rust host and the .NET host run the shared extension id cases
- **THEN** both report the expected outcome for every case
