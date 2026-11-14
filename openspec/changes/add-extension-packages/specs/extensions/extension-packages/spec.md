# Spec Delta

## Purpose

Defines how a Morphir extension can be a package: a tree of files with one entry point, delivered as one archive. It covers:

- what the release descriptor, the repository index record, the installed catalog and the extension lock record for a package;
- how a host reads, checks and unpacks a package;
- where a package is stored, how a host starts it, and how it is removed;
- what a host may conclude from a package.

A single-file artifact that is the executable itself keeps its meaning.

This corrects the inherited STORE-1 procedure, which incorrectly used the activation check for reuse and omitted the repair lease. Full hashing at install and on request, cheap `VERIFY-B` only at activation, and `LAUNCH-A` are unchanged. Reuse hashing under the state lock costs time proportional to the existing tree's bytes; the lock is not promised to last milliseconds.

Terms used on this page:

| Term | Meaning |
| --- | --- |
| single-file artifact | A descriptor artifact with no `package` member. The delivered file is the executable or module that runs, as before this change. |
| package | A descriptor artifact with a `package` member. Its delivered file is an archive that is unpacked before anything runs. |
| archive | The delivered file of a package: a ZIP file or a gzip-compressed tar file. |
| entry | One member of an archive, in the order this page defines for its format. |
| entry name | An entry's path in the archive, read as this page defines for its format. |
| tree | The regular files a package installs, each with a path, its bytes and an executable flag. |
| tree path | A file's path in the tree: its entry name without the optional root, with `/` separators. |
| entry point | The tree path of the file a host starts. |
| tree manifest | The canonical text that lists the tree. |
| tree digest | The SHA-256 of the tree manifest's bytes. |
| package version | The first version of the extension state family whose schemas carry `package`. |
| published package | A tree at its place in the store, `store/extensions/packages/sha256/<tree digest>/`. |

Entry names are ASCII in this version. That removes Unicode normalization, unassigned code points and Unicode case mapping from the unpacking rules. The maintainer may lift the limit in a later version.

The descriptor, index record, catalog and extension lock belong to the extension state family, which has one version carried by a `$schema` URL (maintainer, Decision 15, 10 November 2026). The package version depends on the order in which this change and finos/morphir#1149 are delivered. The approval-time audit in `docs/spec/extensions/publication-audit.md` establishes PKGVER-A and selects `0.1.0-preview.1`. The approved rule is:

| Outcome | When | Package version | Its schema URLs |
| --- | --- | --- | --- |
| `PKGVER-A` | The family's `0.1.0-preview.1` schemas are not yet published, and no released host, publisher or tool reads or writes `0.1.0-preview.1`, when this change is approved | `0.1.0-preview.1`, defined together with #1149 | `https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/<file>.schema.json` |
| `PKGVER-B` | Otherwise | `0.1.0-preview.2` | `https://morphir.finos.org/schemas/extensions/0.1.0-preview.2/<file>.schema.json` |

A host built against #1149 without this change refuses a package under either outcome, because `package` is always listed in `critical`.

A worked example: morphir-dotnet's F# frontend `org.finos.morphir.fsharp-frontend` 0.6.0 for `x86_64-pc-windows-msvc` is a self-contained .NET program of about 239 files and 121 MB. It is published as `fsharp-frontend-0.6.0-win-x64.zip`, a package with entry point `morphir-fsharp-frontend.exe`.

## ADDED Requirements

### Requirement: A package is declared by its descriptor artifact
A release descriptor artifact SHALL be a package when it has a `package` member, and a single-file artifact otherwise. `package` SHALL have the members `format`, `entryPoint` and `treeSha256`, and MAY have `root` and `executables`. A package SHALL have `runtime` `process`. A reader of `0.1.0-preview.3` SHALL refuse a `package` member on any other runtime with `package.runtime`.

#### Scenario: A process package
- **WHEN** a descriptor artifact has `runtime` `process`, `filename` `fsharp-frontend-0.6.0-win-x64.zip` and a `package` member with `format` `zip`, `entryPoint` `morphir-fsharp-frontend.exe` and a `treeSha256`
- **THEN** a reader reads it as a package

#### Scenario: A WASM artifact cannot be a package
- **WHEN** a descriptor artifact has `runtime` `wasm` and a `package` member
- **THEN** the reader refuses the descriptor with `package.runtime`

### Requirement: The family's published schemas carry the package member
The published schemas of the release descriptor, index record, catalog and extension lock at `0.1.0-preview.3` SHALL define the `package` member, its members and their types. A document that carries `package` SHALL be valid against them.

#### Scenario: A package descriptor validates
- **WHEN** an editor validates the F# frontend's `release.json` against the schema its `$schema` names
- **THEN** the schema accepts its `package` member with `format`, `root`, `entryPoint` and `treeSha256`

### Requirement: A document that carries a package lists it as critical
A descriptor or index record with a package artifact SHALL list `artifacts.package` in its top-level `critical` list, and a catalog with a package entry SHALL list `extensions.package`. A reader of `0.1.0-preview.3` SHALL refuse such a document without that path with `package.not_critical`. A reader that does not understand `package` therefore refuses the document by the must-ignore-unless-critical rule.

#### Scenario: A host built without this change meets a package
- **WHEN** a host that implements the family version without this change reads a descriptor at that version whose artifact has `package` and whose `critical` lists `artifacts.package`
- **THEN** it refuses the descriptor as naming a critical member it does not understand, and stores and starts nothing

#### Scenario: A package that is not marked critical
- **WHEN** a reader of `0.1.0-preview.3` reads a descriptor with a `package` member and no `artifacts.package` in `critical`
- **THEN** it refuses the descriptor with `package.not_critical`

### Requirement: A single-file artifact is the executable itself
An artifact without a `package` member SHALL be read, stored, recorded and started exactly as a single-file artifact was before this change. A reader of `0.1.0-preview.3` SHALL refuse a `process` artifact without `package` whose `filename` ends in `.zip`, `.tar.gz`, `.tgz` or `.tar`, ignoring ASCII case, with `package.archive_without_package`, and SHALL NOT store or start it.

#### Scenario: A raw executable is unchanged
- **WHEN** a descriptor lists the process artifact `morphir-scala-elm-linux-amd64-0.5.0-M13`, a raw executable, with no `package` member
- **THEN** a host stores and starts that file as before, and a recipe binds that file as the artifact's target

#### Scenario: An executable shipped inside an archive
- **WHEN** a descriptor lists the process artifact `morphir-elm-extension-0.4.1-x86_64-unknown-linux-gnu.tgz`, which holds one executable, with no `package` member
- **THEN** the reader refuses it with `package.archive_without_package`, and the release is installable only once it is published with a `package` member naming that executable

### Requirement: A package archive is ZIP or gzip-compressed tar
`package.format` SHALL be `zip` or `tar.gz`. The artifact's `filename` SHALL end in `.zip` for `zip`, and in `.tar.gz` or `.tgz` for `tar.gz`, compared ignoring ASCII case. A reader SHALL refuse any other value, or a file name that does not match the format, with `package.archive_format`.

#### Scenario: A format that does not match the file name
- **WHEN** a package has `format` `zip` and `filename` `frontend.tgz`
- **THEN** the reader refuses the descriptor with `package.archive_format`

### Requirement: A ZIP archive's entries come from its central directory
A host SHALL read a ZIP archive's entries, in order, from its central directory, found through the end-of-central-directory record and, when present, its zip64 record. Zip64 records and extra fields SHALL be accepted. An entry's name is its central-directory file name. An entry is a directory exactly when its name ends in `/`.

#### Scenario: Central-directory order decides the first fault
- **WHEN** a ZIP archive's central directory lists `../x` first and `CON` second, while `CON`'s data comes first in the file
- **THEN** the host refuses it with `package.parent_component` for `../x`

### Requirement: A ZIP archive has no hidden or overlapping bytes
A host SHALL refuse with `package.zip_layout` a ZIP archive whose end record is missing or names another disk, that has bytes before the first local header, between entries or overlapping, or that has any byte after the end record and its comment. It SHALL check every entry's local header against the central directory before it applies the entry rules.

#### Scenario: A self-extracting prefix
- **WHEN** a ZIP archive is preceded by an executable stub
- **THEN** the host refuses it with `package.zip_layout`

### Requirement: Each ZIP local header matches its central entry
A host SHALL refuse with `package.zip_header_mismatch` an entry whose local header differs from its central entry in name, compression method, flags, CRC-32, compressed size or uncompressed size, or, when flag bit 3 is set, whose data descriptor differs from the central entry.

#### Scenario: A local header that lies about its name
- **WHEN** a central entry is named `run` and its local header is named `../run`
- **THEN** the host refuses the archive with `package.zip_header_mismatch`

### Requirement: Unsupported ZIP features are refused
A host SHALL refuse with `package.zip_unsupported` an entry that is encrypted (flag bit 0 or 6), that uses a compression method other than 0 (stored) or 8 (deflate), or that carries an Info-ZIP Unicode Path extra field (`0x7075`). It SHALL refuse with `package.zip_crc` an entry whose decompressed bytes do not have its CRC-32 or uncompressed size.

#### Scenario: An encrypted entry
- **WHEN** a package archive is a ZIP file with an encrypted entry
- **THEN** the host refuses it with `package.zip_unsupported` and unpacks nothing

### Requirement: A ZIP entry's type agrees with its name
When an entry's version-made-by high byte is 3 (Unix) and its external attributes' high 16 bits are not zero, a host SHALL read their file type. A symbolic link is `package.link_entry`. A character device, block device, FIFO or socket is `package.special_entry`. A directory type on a name without `/`, or a regular type on a name with `/`, is `package.entry_type_mismatch`. So is the DOS directory attribute (`0x10`) on a name without `/`.

#### Scenario: A link that looks like a file
- **WHEN** a ZIP entry `lib/current` has version-made-by 3, Unix mode `0120777` and no trailing `/`
- **THEN** the host refuses it with `package.link_entry`

### Requirement: A gzip stream holds one member
A host SHALL refuse with `package.gzip_layout` a `tar.gz` archive that is not exactly one gzip member as RFC 1952 defines it, with a CRC-32 and size trailer that match the decompressed bytes and no byte after the member.

#### Scenario: Two gzip members
- **WHEN** a `tar.gz` archive is two gzip members concatenated
- **THEN** the host refuses it with `package.gzip_layout`

### Requirement: A tar stream is read block by block
A host SHALL read 512-byte headers in stream order, and SHALL refuse with `package.tar_layout` a header with a wrong checksum, a stream without two consecutive zero blocks, a non-zero byte after them, a malformed pax record, or a pax or GNU long-name header that is repeated before one entry or followed by no entry. It SHALL read the size in octal or in GNU base-256.

#### Scenario: A missing end of archive
- **WHEN** a `tar.gz` archive's tar stream ends after its last entry's data without two zero blocks
- **THEN** the host refuses it with `package.tar_layout`

### Requirement: A tar entry's name and size are read in a fixed order
A tar entry's name SHALL be the `path` of the pax extended header (`x`) before it, else the payload of the GNU long-name header (`L`) before it up to its first NUL, else, when its magic is `ustar` followed by NUL and its prefix is not empty, its prefix, `/` and name, else its name. Its size SHALL be the pax `size` when given. A host SHALL ignore other pax keys.

#### Scenario: A GNU long name
- **WHEN** a tar stream holds an `L` header whose payload is `lib/a-very-long-name.dll` followed by a regular entry named `././@LongLink`
- **THEN** the host reads one regular entry named `lib/a-very-long-name.dll`

### Requirement: Only some tar entry types are accepted
A tar entry of type `0` or NUL SHALL be a regular file and of type `5` a directory; `x` and `L` are headers for the next entry. Types `1`, `2` and `K` SHALL be refused with `package.link_entry`, types `3`, `4` and `6` with `package.special_entry`. Every other type, and a pax key starting `GNU.sparse.`, SHALL be refused with `package.tar_unsupported`. A type `0` entry whose name ends in `/` is `package.entry_type_mismatch`.

#### Scenario: Contiguous and global headers
- **WHEN** tar streams hold a type `7` entry, a type `g` header and a pax key `GNU.sparse.map`
- **THEN** the host refuses each with `package.tar_unsupported`

### Requirement: Tar extension headers are bounded
A host SHALL refuse a pax or GNU long-name header whose payload exceeds 1 MiB with `package.tar_header_too_large`, before it reads the payload.

#### Scenario: A huge pax header
- **WHEN** a tar stream holds a pax header whose size field says 2 MiB
- **THEN** the host refuses it with `package.tar_header_too_large` without buffering it

### Requirement: A directory entry carries no bytes
A directory entry with a size other than zero SHALL be refused with `package.directory_with_data`. A directory entry SHALL create no file. A host SHALL NOT create a directory that holds no file of the tree.

#### Scenario: A directory with data
- **WHEN** a ZIP entry `lib/` has an uncompressed size of 10
- **THEN** the host refuses it with `package.directory_with_data`

### Requirement: A leading dot segment is removed once
Before the entry rules, a host SHALL ignore an entry whose name is exactly `./`, and SHALL remove one leading `./` from every other entry name. Entries that then share a name are duplicates.

#### Scenario: An archive made from inside its directory
- **WHEN** a `tar.gz` archive made by `tar -C dist -czf x.tgz .` holds `./`, `./run` and `./lib/a.dll`
- **THEN** the host reads the entries `run` and `lib/a.dll`

### Requirement: Entry names are ASCII in this version
Every byte of an entry name SHALL be from `0x20` to `0x7E`. A host SHALL refuse a name with a byte of `0x80` or more with `package.non_ascii_name`, whatever the archive's flags say about its encoding. This is a limit of this version, not of Morphir paths in general.

#### Scenario: A non-ASCII name
- **WHEN** an archive holds `notes/café.txt`
- **THEN** the host refuses it with `package.non_ascii_name`

### Requirement: Entry paths are relative, forward-slash and non-traversing
A host SHALL refuse an entry name that contains `\` with `package.backslash`, that starts with `/` with `package.absolute_path`, or whose first component is an ASCII letter followed by `:` with `package.drive_letter`. It SHALL refuse an empty or `.` component with `package.empty_or_dot_component`, and a `..` component with `package.parent_component`. One trailing `/` on a directory entry is not an empty component.

#### Scenario: Traversing and absolute paths
- **WHEN** archives hold the entries `../evil.dll`, `/etc/passwd`, `C:/x.dll`, `a\b.dll` and `a//b.dll`
- **THEN** the host refuses them with `package.parent_component`, `package.absolute_path`, `package.drive_letter`, `package.backslash` and `package.empty_or_dot_component`

### Requirement: Entry path components are portable names
A host SHALL refuse a component that contains a byte below `0x20`, `0x7F`, or one of `< > : " | ? *` with `package.reserved_character`, and one that ends in `.` or a space with `package.trailing_dot_or_space`. It SHALL refuse with `package.device_name` a component whose part before its first `.`, with trailing spaces removed and compared ignoring ASCII case, is `CON`, `PRN`, `AUX`, `NUL`, `CONIN$`, `CONOUT$`, or `COM` or `LPT` followed by one digit from `1` to `9`.

#### Scenario: Windows names that cannot be stored
- **WHEN** archives hold the entries `lib/CON.dll`, `com1`, `notes.`, `notes ` and `lib/a:b`
- **THEN** the host refuses them with `package.device_name`, `package.device_name`, `package.trailing_dot_or_space`, `package.trailing_dot_or_space` and `package.reserved_character`

### Requirement: Entry paths are bounded
An entry name SHALL have at most 240 bytes, and each component at most 255. A tree path SHALL have at most 120 bytes and 16 components. A host SHALL refuse a longer name or tree path with `package.path_length`, and a deeper tree path with `package.nesting_depth`. With ASCII names a byte and a UTF-16 code unit are the same count.

#### Scenario: A tree path one past the limit
- **WHEN** an archive holds a file whose tree path has 121 bytes, and another whose tree path has 17 components
- **THEN** the host refuses them with `package.path_length` and `package.nesting_depth`

### Requirement: A declared root strips one directory prefix
`package.root`, when present, SHALL be one or more components joined by `/`, with no leading or trailing `/`, each following the component rules. Every file entry SHALL lie under it, and its tree path is its entry name without the root and the following `/`. A directory entry for the root or one of its ancestors is allowed. Any other entry outside the root SHALL be refused with `package.outside_root`.

#### Scenario: A file outside the declared root
- **WHEN** a package with `root` `fsharp-frontend` holds `fsharp-frontend/morphir-fsharp-frontend.exe` and `README.txt`
- **THEN** the host refuses the archive with `package.outside_root`, naming `README.txt`

### Requirement: No two entries share a name on any first-delivery file system
A host SHALL refuse an entry whose name equals an earlier entry's with `package.duplicate_entry`. It SHALL refuse with `package.file_directory_conflict` a file whose name is an earlier entry's directory, or a directory whose name is an earlier file's. It SHALL refuse with `package.case_collision` an entry with a prefix, cut at a `/`, that equals a different earlier prefix after mapping `A`–`Z` to `a`–`z`.

#### Scenario: Case and file-directory collisions
- **WHEN** archives hold `lib/A.dll` then `lib/a.dll`, `Lib/x.dll` then `lib/y.dll`, `lib/x.dll` then `lib/x.dll/y`, and `run` twice
- **THEN** the host refuses them with `package.case_collision`, `package.case_collision`, `package.file_directory_conflict` and `package.duplicate_entry`

### Requirement: Archive size, entry count and unpacked size are bounded
A host SHALL refuse an archive over 256 MiB with `package.archive_too_large` before reading it. It SHALL refuse more than 4096 entries with `package.entry_count`, a file over 256 MiB with `package.file_too_large`, and more than 1 GiB of file bytes in total with `package.unpacked_size`. Sizes SHALL be counted as bytes are decompressed, not taken from headers.

#### Scenario: A decompression bomb
- **WHEN** a 1 MiB archive's entries decompress to more than 1 GiB
- **THEN** the host stops decompressing at the limit, refuses the archive with `package.unpacked_size`, and removes what it wrote

### Requirement: The entry point and executables exist in the tree
A host SHALL refuse a package whose `entryPoint` is not the tree path of a file with `package.entry_point_missing`, and one with a path in `executables` that is not the tree path of a file with `package.executable_missing`. For a platform whose target triple contains `-windows-`, the entry point's last component SHALL end in `.exe`, ignoring ASCII case; otherwise the host SHALL refuse it with `package.entry_point_not_exe`.

#### Scenario: A Windows entry point that is not an executable
- **WHEN** a package for `x86_64-pc-windows-msvc` has `entryPoint` `run.cmd`
- **THEN** the host refuses it with `package.entry_point_not_exe`

### Requirement: Refusals follow a fixed order
A host SHALL report only the first refusal (codes here omit `package.`): `archive_too_large`, `archive_digest_mismatch`, `archive_format`. A ZIP archive then gets `zip_layout` and `zip_header_mismatch` over the whole archive, then its entries. A tar.gz archive gets the gzip header's `gzip_layout`, its entries, the tar end's `tar_layout`, then the gzip trailer's `gzip_layout`. The tree rules come last.

#### Scenario: A bad archive is refused before its entries
- **WHEN** a package's archive does not match its `sha256` and also holds the entry `../x`
- **THEN** the host refuses it with `package.archive_digest_mismatch`

#### Scenario: A bad gzip trailer after a bad entry
- **WHEN** a `tar.gz` archive holds the entry `../x` and its gzip trailer has a wrong CRC-32
- **THEN** the host refuses it with `package.parent_component`, because a streaming reader meets the entry first

### Requirement: The tree rules come after the entries
After every entry, a host SHALL apply `entry_point_missing`, `entry_point_not_exe`, `executable_missing`, `tree_digest_mismatch` and then `install_path_too_long`, each prefixed `package.`.

#### Scenario: A missing entry point before a wrong digest
- **WHEN** a package names an entry point that is not in the tree, and its tree digest also differs
- **THEN** the host refuses it with `package.entry_point_missing`

### Requirement: Format rules come first for each entry
For each entry a host SHALL first apply, in this order: `entry_count`, `zip_unsupported`, `tar_layout`, `tar_header_too_large`, `tar_unsupported`, `entry_type_mismatch`, `link_entry`, `special_entry`, `directory_with_data`, each prefixed `package.`.

#### Scenario: A link with a traversing name
- **WHEN** a tar stream holds a symbolic link entry named `../x`
- **THEN** the host refuses it with `package.link_entry`

### Requirement: Name and size rules follow for each entry
After the format rules, a host SHALL apply, in this order: `non_ascii_name`, `backslash`, `absolute_path`, `drive_letter`, `empty_or_dot_component`, `parent_component`, `reserved_character`, `trailing_dot_or_space`, `device_name`, `path_length`, `nesting_depth`, `outside_root`, `duplicate_entry`, `file_directory_conflict`, `case_collision`, `file_too_large`, `unpacked_size`, `zip_crc`, each prefixed `package.`.

#### Scenario: An entry that breaks two rules
- **WHEN** an archive holds the entry `../CON`
- **THEN** the host refuses it with `package.parent_component`, not `package.device_name`

### Requirement: The descriptor, record and lock carry the archive digest and the tree digest
The artifact's `sha256` SHALL be the SHA-256 of the archive's bytes. `package.treeSha256` SHALL be the tree digest. The index record and the catalog entry of a package SHALL carry the artifact's `package` member unchanged, and the extension lock SHALL record the artifact digest and the `package` member unchanged.

#### Scenario: A lock records both digests
- **WHEN** a host installs the F# frontend package
- **THEN** its extension lock records the archive's SHA-256 as the artifact digest and the descriptor's `package` member, including `treeSha256`

### Requirement: The tree manifest is canonical text
The tree manifest SHALL be ASCII text without a byte order mark: the line `morphir-package-tree 0.1.0-preview.1`, then one line per file in ascending byte order of its tree path. Each file line SHALL be its kind (`x` for executable, `f` otherwise), its size in decimal without leading zeros (`0` for an empty file), its SHA-256 in lowercase hexadecimal and its tree path, separated by one space. Every line SHALL end with one LF. A reader SHALL split a line at its first three spaces only.

#### Scenario: A tree with an empty file and a space in a name
- **WHEN** a tree holds `run` (5 bytes, executable), `lib/a.dll` (3 bytes) and `docs/read me.txt` (0 bytes)
- **THEN** its manifest is `morphir-package-tree 0.1.0-preview.1`, then `f 0 <sha256 of empty> docs/read me.txt`, then `f 3 <sha256 of a.dll> lib/a.dll`, then `x 5 <sha256 of run> run`, each followed by LF

### Requirement: The tree digest covers paths, bytes and executable flags only
A file's kind SHALL be `x` when its tree path is the entry point or is listed in `package.executables`, and `f` otherwise. A file's SHA-256 SHALL be computed over its bytes after decompression, with line endings and encodings untouched. No owner, group, timestamp, permission bit or extended attribute from the archive SHALL affect the manifest.

#### Scenario: Archive metadata does not change the digest
- **WHEN** two archives hold the same files with the same tree paths and bytes, one with Unix mode `0644` and new timestamps, the other with mode `0755` and old timestamps
- **THEN** both give the same tree digest for the same `entryPoint` and `executables`

### Requirement: A package is verified before it is published
A host SHALL treat a package as verified when the archive's SHA-256 equals the artifact's `sha256`, no rule refuses it, and the tree digest it computes from the bytes it writes equals `package.treeSha256`. It SHALL refuse a different archive digest with `package.archive_digest_mismatch` and a different tree digest with `package.tree_digest_mismatch`. A package that is not verified SHALL NOT be published, recorded or started.

#### Scenario: A wrong tree digest
- **WHEN** a package's archive matches its `sha256` but its files give another tree digest than `package.treeSha256`
- **THEN** the host refuses it with `package.tree_digest_mismatch` and publishes nothing

### Requirement: A published package is stored by its tree digest
A host SHALL publish a verified package at `store/extensions/packages/sha256/<treeSha256>/`, holding the tree manifest as `manifest` and the files under `tree/`, with its lease file `store/extensions/packages/sha256/<treeSha256>.lease` beside it. A host SHALL NOT change a published package's files, except for exclusive-lease repair under `A package is published and recorded in one state-lock scope` or collection under `Collection removes only unused packages`.

#### Scenario: The F# frontend in the store
- **WHEN** a host publishes the F# frontend package
- **THEN** `store/extensions/packages/sha256/<treeSha256>/tree/morphir-fsharp-frontend.exe` and the other 238 files exist, `manifest` holds the tree manifest, and the lease file sits beside the directory

### Requirement: A published package is read-only
On Unix a host SHALL give `x` files mode `0555`, `f` files mode `0444` and, once the package is published, its directories mode `0555`, with no other permission bit. On Windows it SHALL set the read-only attribute on every file and SHALL write no alternate data stream. These modes make accidental writes fail; a process with the user's rights can still change them.

#### Scenario: A guest that writes beside itself
- **WHEN** a guest started from a published package on Linux tries to create `tree/log.txt`
- **THEN** the write fails with a permission error at that moment

### Requirement: A package is staged and verified outside the state lock
A host SHALL create and exclusively lock `store/extensions/packages/.stage-<random>.owner`, opened as lock files are, before it creates `store/extensions/packages/.stage-<random>/`. It SHALL unpack and verify there, holding the owner lock until it has published or removed the staging directory. A host SHALL remove another's staging directory and owner file only when it can take the owner lock without waiting, and SHALL remove a staging directory that has no owner file.

#### Scenario: An interrupted unpack is never selected
- **WHEN** a host stops while unpacking the F# frontend
- **THEN** only a `.stage-` directory and its owner file exist, no lock or catalog entry names the package, and the next cleanup removes both once the owner lock is free

### Requirement: A package is published and recorded in one state-lock scope
Under one hold of the state lock, a host SHALL fully verify an existing tree before reuse, or publish verified staging if none exists. A bad tree SHALL be replaced only under the repair requirements below. The host SHALL set directory modes and write the lock and catalog through the journal before releasing the state lock.

#### Scenario: Collection cannot run between publication and recording
- **WHEN** a host publishes the F# frontend while another process runs collection in the same home
- **THEN** collection runs wholly before the publication or wholly after the recording, and never removes a tree that the new lock names

### Requirement: Install fully verifies an existing tree before reuse
Before reusing an existing published tree, a host SHALL check the manifest digest against `treeSha256`, exact regular-file names, sizes and read-only modes, and rehash every file against the manifest. Only a tree passing this full check SHALL be reused. The activation-only `VERIFY-B` check SHALL NOT substitute for install verification.

#### Scenario: A same-size changed tree is not reused at install
- **WHEN** install finds an existing tree whose manifest, names, sizes and modes match, but one file has a changed byte, and its lease is free
- **THEN** full per-file hashing detects the change, the host takes the exclusive nonwaiting lease, replaces the corrupt tree with verified staging while retaining the same lease file identity, and records only the verified replacement

### Requirement: Repair holds an exclusive nonwaiting lease
Before changing modes, moving or replacing a bad existing tree, a host SHALL take its lease exclusively without waiting under the state lock. A live shared lease SHALL cause `package.publish_busy`, leaving tree, manifest, modes, lease file, lock and catalog unchanged, with staging left for cleanup. The host SHALL NOT wait for a guest under the state lock, and SHALL retain an acquired exclusive lease through repair and journal recording.

#### Scenario: A corrupt tree with a live lease is left unchanged
- **WHEN** install finds that same corruption while a running guest holds a shared lease on the existing tree
- **THEN** exclusive lease acquisition fails without waiting, install refuses with `package.publish_busy`, and tree bytes, manifest, modes, lease identity, lock and catalog remain unchanged; staging is left for cleanup

### Requirement: Repair preserves the lease file identity
When repairing a bad existing tree, a host SHALL retain the existing lease file's identity. It SHALL NOT unlink, recreate or replace that lease file. With its exclusive lease held, it SHALL move the bad tree to `.trash-<random>` and publish verified staging, then set directory modes and journal the lock and catalog.

#### Scenario: Repair retains the existing lease file
- **WHEN** the corrupt tree's last shared lease has ended and install can acquire its exclusive lease
- **THEN** it replaces the bad tree from verified staging while holding that same lease file, and another activation subsequently acquires a shared lease on the same file identity

### Requirement: A rename never replaces and never copies
A host SHALL publish with a rename that fails when the target exists: `renameat2` with `RENAME_NOREPLACE` on Linux, `renamex_np` with `RENAME_EXCL` on macOS, `MoveFileExW` without `MOVEFILE_REPLACE_EXISTING` on Windows. It SHALL retry a sharing or access error for up to 10 seconds, then fail with `package.publish_busy`. A cross-volume error SHALL fail with `package.store_not_one_volume`, without copying.

#### Scenario: A scanner holds a new file open
- **WHEN** on Windows a real-time scanner holds a staged executable open and the first rename fails with a sharing violation
- **THEN** the host retries, and either publishes within 10 seconds or fails with `package.publish_busy`, leaving the staging directory for cleanup

### Requirement: A host starts a package's entry point from the store
A host SHALL start a package by the absolute path of its entry point under `store/extensions/packages/sha256/<treeSha256>/tree/`, in the platform's native spelling without a verbatim prefix. The argument vector SHALL be that path followed by the locked arguments. The working directory SHALL be the project directory for a project command, otherwise a new private directory outside the store.

#### Scenario: Starting the F# frontend
- **WHEN** the Native AOT host activates the F# frontend for a project compile on Windows
- **THEN** it starts `<home>\store\extensions\packages\sha256\<treeSha256>\tree\morphir-fsharp-frontend.exe` with the locked arguments, in the project directory

### Requirement: Activation checks the published tree
Before starting a package, a host SHALL check under the state lock that the lock and catalog agree on `package`, that the SHA-256 of `manifest` equals `treeSha256`, and that `tree/` holds exactly the manifest's files as regular files, with the manifest's sizes and, on Unix, the modes of the read-only rule. This is the decided `VERIFY-B` activation check; full verification of every file is required at install and on request as stated below.

#### Scenario: A file is missing
- **WHEN** a file listed in the F# frontend's manifest has been deleted from the store
- **THEN** activation refuses with `package.tree_changed` and starts nothing

### Requirement: A full verification is available on request
A host SHALL verify every file of an installed package against its manifest when it installs the package and when the user asks it to verify installed extensions. A failure SHALL be reported with `package.tree_changed`, naming the file.

#### Scenario: A changed byte is found on request
- **WHEN** one byte of an F# frontend assembly in the store has changed and the user asks the host to verify installed extensions
- **THEN** the host reports `package.tree_changed` and names the file

### Requirement: Windows store paths fit the process and directory APIs
On Windows, before it publishes, a host SHALL refuse a package when the absolute store path of any of its files would exceed 259 UTF-16 code units, or of any of its directories 247, with `package.install_path_too_long`, naming the longest path and its length. A host SHALL NOT use the verbatim prefix to write a package.

#### Scenario: A long user name on Windows
- **WHEN** the home is `C:\Users\<name>\.morphir` and the user name plus the package's longest tree path exceed 137 characters
- **THEN** the host refuses the install with `package.install_path_too_long` before it publishes anything

### Requirement: A running package holds a lease for its whole process tree
A host SHALL take a shared lock on the package's lease file under the state lock at activation. It SHALL keep the lease until the started process and every descendant have exited. On Unix it SHALL pass the leased descriptor to the started process as an inherited descriptor, and start that process in a new process group. On Windows it SHALL start the process in a job object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` and no breakaway.

#### Scenario: Two sessions share a package
- **WHEN** two compiles run the F# frontend at the same time
- **THEN** both hold a shared lease on the same lease file and neither blocks the other

#### Scenario: The host crashes while its guest runs on Unix
- **WHEN** the host process is killed while the F# frontend it started is compiling
- **THEN** the frontend still holds the inherited lease, and collection keeps the package until the frontend and its descendants have exited

### Requirement: A host ends the process tree before it releases the lease
At the end of a session a host SHALL wait for the started process to exit, then end any process left in its process group (Unix) or job (Windows) before it releases its own lease. On Windows a host crash closes the job, which ends every process in it.

#### Scenario: A guest leaves a child behind
- **WHEN** the F# frontend exits normally but leaves a child process running
- **THEN** the host ends that child before it releases the lease

### Requirement: Uninstall does not delete a package
Uninstalling or updating an extension SHALL remove or replace its lock and catalog entry and SHALL NOT delete or change any published package.

#### Scenario: Uninstall while running
- **WHEN** a user uninstalls the F# frontend while a compile is running it
- **THEN** the lock and catalog entry are removed, the running process continues, and its files stay in the store

### Requirement: Collection removes only unused packages
A host SHALL delete a published package only on an explicit collection command, under the state lock. It SHALL do so only when no extension lock in `locks/extensions/` names its tree digest, backups not counted, and it can take an exclusive lock on its lease without waiting. It SHALL clear the read-only modes, rename the package to `.trash-<random>`, then delete it. A failed rename SHALL leave the package in place.

#### Scenario: A package in use is kept
- **WHEN** collection runs while a process started from an unreferenced package still holds its lease
- **THEN** collection leaves that package in place and reports it as in use

### Requirement: Collection keeps packages a toolchain generation may use
Until the toolchain contracts define how a generation receipt names a package, a host SHALL collect no package in a home that holds any toolchain generation receipt under `toolchains/generations/`.

#### Scenario: A home with a toolchain generation
- **WHEN** collection runs in a home whose `toolchains/generations/` holds a receipt
- **THEN** it deletes no package and says why

### Requirement: A package grants no trust
A package SHALL NOT change who is trusted. A host MAY conclude from a verified package that its tree is the one the descriptor names, and so, when the descriptor is authenticated, the one its publisher released. A host SHALL NOT conclude publisher identity from unpacking, SHALL NOT treat code signatures inside the tree as authentication, and SHALL still decide claims by the probe.

#### Scenario: A signed executable inside an unsigned release
- **WHEN** a package from an unauthenticated local repository holds an entry point with a valid Authenticode signature
- **THEN** the host treats the release as unauthenticated developer content, and the signature grants nothing

### Requirement: A host that cannot install packages refuses them
A host that reads `0.1.0-preview.3` but does not install packages SHALL refuse a package artifact with `package.unsupported`, naming the artifact, and SHALL NOT store or start its archive as a single file.

#### Scenario: A host without package support
- **WHEN** a host without package support selects the F# frontend's package artifact
- **THEN** it refuses with `package.unsupported` and installs nothing

### Requirement: Hosts prove the package rules against shared cases
The package rules SHALL be published as language-neutral cases: valid packages in both formats, one case per refusal code except `install_path_too_long`, `publish_busy` and `store_not_one_volume`, tree manifests with their digests, and both single-file shapes. Every host that installs packages SHALL run them and report each expected code and entry name. The `archive_too_large` case SHALL state a length without bytes. Leases, renames and paths SHALL be proved by host tests.

#### Scenario: Two hosts agree on every case
- **WHEN** the .NET host and the MoonBit host run the shared package cases
- **THEN** both report the expected outcome for every case
