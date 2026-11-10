# Spec Delta

## Purpose

Defines the identity of a Morphir extension: the grammar of its id, how ids are compared, what an id does and does not mean, the file and key names a host derives from it, and the contract versions that carry the new grammar. Every host, repository and toolchain contract that names an extension follows it.

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

### Requirement: Names derived from an id are the id with a fixed suffix
Wherever a host or repository derives a file name or a key from an extension id, it SHALL use the whole id followed by a fixed suffix, such as `<id>.jsonl`, `<id>.json` or `<id>.json.transaction`. Two different ids SHALL never derive the same name. The content-addressed artifact store SHALL NOT use the id in its paths.

#### Scenario: Derived names do not collide
- **WHEN** a host installs `acme.tools` and `acme-tools` and records their locks
- **THEN** it writes the two locks as `locks/extensions/acme.tools.json` and `locks/extensions/acme-tools.json`, and no name it derives for one equals a name it derives for the other on any first-delivery platform, including case-insensitive file systems

#### Scenario: A repository history is found by its full id
- **WHEN** a repository index holds `extensions/org.finos.morphir.fsharp-frontend.jsonl`
- **THEN** a reader takes the id `org.finos.morphir.fsharp-frontend` from the file name and refuses the file if its records name another id

### Requirement: One catalog, one lock directory and one history directory hold every id
A Morphir home SHALL record every installed extension, whatever the form of its id, in the one catalog `catalog/extensions.json` and the one lock directory `locks/extensions/`, under the one state lock `locks/extensions.state.lock`. A repository index SHALL keep every history in `extensions/<id>.jsonl`.

#### Scenario: A dotted install beside a single-segment one
- **WHEN** a host installs `org.finos.morphir.fsharp-frontend` into a home that holds `morphir-elm`
- **THEN** `catalog/extensions.json` lists both, in id order, and the new lock is `locks/extensions/org.finos.morphir.fsharp-frontend.json`

### Requirement: The documents that can carry a dotted id are at new exact drafts
A writer SHALL write every release descriptor, repository index record and installed catalog at `2.0.0-draft.3`, and every extension lock at `2.0.0-draft.1`, whatever the form of the ids it names. `2.0.0-draft.3` differs from `2.0.0-draft.2` only in the id grammar, and the lock's `2.0.0-draft.1` differs from `"1.0"` only in the id grammar.

#### Scenario: A single-segment release is written at the new draft
- **WHEN** a publisher authors a release with the id `morphir-elm`
- **THEN** its descriptor has `schemaVersion` `2.0.0-draft.3`

#### Scenario: A dotted id at an earlier version is refused
- **WHEN** a reader reads a `2.0.0-draft.2` descriptor or a `"1.0"` lock that names `org.finos.morphir.fsharp-frontend`
- **THEN** it refuses the document, because no earlier version allows a dotted id

### Requirement: A reader of the new drafts reads only the current drafts
A reader of these documents SHALL read `2.0.0-draft.3` (descriptor, index record, catalog) and `2.0.0-draft.1` (lock). It need not read `2.0.0-draft.1` or `2.0.0-draft.2` descriptors, records or catalogs, or `"1.0"` locks, and no conversion between versions is part of this contract. A reader that does not read a version refuses the document with an unsupported-version error that names the file and the versions it reads.

#### Scenario: A current host meets an earlier catalog
- **WHEN** a host that reads only the current drafts finds a `2.0.0-draft.2` `catalog/extensions.json`
- **THEN** it refuses that catalog as an unsupported extension schema version, names the file and the versions it reads, and changes nothing

### Requirement: Hosts that predate this change are not protected
A writer SHALL write the new drafts in every home and repository, including one that a host reading only earlier versions also uses. Keeping such a host working is not a goal of this change. That host refuses each document at the new drafts with its existing unsupported-version error, before it reads any id.

#### Scenario: An earlier reader refuses the new drafts by version
- **WHEN** a reader that reads only `"1.0"`, `2.0.0-draft.1` and `2.0.0-draft.2` reads a `2.0.0-draft.3` descriptor, index record or catalog
- **THEN** it refuses the document as an unsupported extension schema version and changes nothing

### Requirement: Project configuration quotes a dotted id
A dotted id SHALL appear in project configuration as one quoted TOML key, such as `[extensions."org.finos.morphir.fsharp-frontend"]`. A configuration reader SHALL refuse an `extensions` entry whose key is not a valid id or whose value nests further tables in place of the extension's settings. The refusal SHALL show the quoted spelling. Diagnostics that print a configuration key for a dotted id SHALL print it quoted.

#### Scenario: An unquoted dotted key is refused
- **WHEN** a project configuration has `[extensions.org.finos.morphir.fsharp-frontend]`
- **THEN** the reader refuses it and suggests `[extensions."org.finos.morphir.fsharp-frontend"]`

#### Scenario: A single-segment key is unchanged
- **WHEN** a project configuration has `[extensions.morphir-elm]`
- **THEN** the reader reads it as before

### Requirement: Hosts prove the rule against shared cases
The id grammar, the device-name rule, the length boundary, exact comparison, derived names, the version rules and configuration quoting SHALL be published as language-neutral cases. Each case names an input and the expected acceptance or refusal. Every host that reads extension ids SHALL run them and report the same outcome for every case.

#### Scenario: Two hosts agree on every case
- **WHEN** the .NET host and the MoonBit host run the shared extension id cases
- **THEN** both report the expected outcome for every case
