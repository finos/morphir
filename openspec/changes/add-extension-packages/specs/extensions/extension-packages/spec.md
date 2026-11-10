# Spec Delta

## Purpose

Defines how a Morphir extension can be a package: a tree of files with one entry point, delivered as one archive. It covers what the release descriptor, the repository index record, the installed catalog and the extension lock record for a package, how a package is checked and unpacked, where it is stored, how a host starts it, how it is removed, and what a host may conclude from it. A single-file artifact keeps its meaning.

Terms used on this page:

| Term | Meaning |
| --- | --- |
| single-file artifact | A descriptor artifact with no `package` member. The delivered file is what runs, as before this change. |
| package | A descriptor artifact with a `package` member. Its delivered file is an archive that is unpacked before anything runs. |
| archive | The delivered file of a package: a ZIP file or a gzip-compressed tar file. |
| tree | The regular files a package installs, each with a path, its bytes and an executable flag. |
| tree path | A file's path in the tree, relative to the tree root, with `/` separators. |
| entry point | The tree path of the file a host starts. |
| tree manifest | The canonical text that lists the tree. |
| tree digest | The SHA-256 of the tree manifest's bytes. |
| package drafts | The first versions of the descriptor, index record, catalog and extension lock that carry `package`. |

The package drafts depend on the order in which this change and finos/morphir#1149 are delivered. Task 1.1 fixes them by this rule:

| Outcome | When | Descriptor, index record, catalog | Extension lock |
| --- | --- | --- | --- |
| `PKGVER-A` | No document has been published at #1149's drafts when this change is approved | `2.0.0-draft.3`, refined in place | `2.0.0-draft.1`, refined in place |
| `PKGVER-B` | A document has been published at #1149's drafts | `2.0.0-draft.4` | `2.0.0-draft.2` |

A worked example: morphir-dotnet's F# frontend `org.finos.morphir.fsharp-frontend` 0.6.0 for `x86_64-pc-windows-msvc` is a self-contained .NET program of about 239 files and 121 MB. It is published as `fsharp-frontend-0.6.0-win-x64.zip`, a package with entry point `morphir-fsharp-frontend.exe`.

## ADDED Requirements

### Requirement: A package is declared by its descriptor artifact
A release descriptor artifact SHALL be a package when it has a `package` member, and a single-file artifact otherwise. `package` SHALL have the members `format`, `entryPoint` and `treeSha256`, and MAY have `root` and `executables`. A package SHALL have `runtime` `process`. A reader of the package drafts SHALL refuse a `package` member on any other runtime with `package.runtime`.

#### Scenario: A process package
- **WHEN** a descriptor artifact has `runtime` `process`, `filename` `fsharp-frontend-0.6.0-win-x64.zip` and a `package` member with `format` `zip`, `entryPoint` `morphir-fsharp-frontend.exe` and a `treeSha256`
- **THEN** a reader reads it as a package

#### Scenario: A WASM artifact cannot be a package
- **WHEN** a descriptor artifact has `runtime` `wasm` and a `package` member
- **THEN** the reader refuses the descriptor with `package.runtime`

### Requirement: A single-file artifact keeps its meaning
An artifact without a `package` member SHALL be read, stored, recorded and started exactly as a single-file artifact was before this change. A host SHALL NOT unpack it, whatever its file name.

#### Scenario: An archive name does not make a package
- **WHEN** a process artifact has the file name `tool.zip` and no `package` member
- **THEN** a host stores and starts `tool.zip` as one file and does not unpack it

### Requirement: A package archive is ZIP or gzip-compressed tar
`package.format` SHALL be `zip` or `tar.gz`. The artifact's `filename` SHALL end in `.zip` for `zip`, and in `.tar.gz` or `.tgz` for `tar.gz`, compared ignoring ASCII case. A reader SHALL refuse any other value or a file name that does not match the format, with `package.archive_format`.

#### Scenario: A format that does not match the file name
- **WHEN** a package has `format` `zip` and `filename` `frontend.tgz`
- **THEN** the reader refuses the descriptor with `package.archive_format`

### Requirement: The archive is read only through its supported features
A host SHALL refuse with `package.archive_format` an archive it cannot read completely, a ZIP archive that is encrypted, spans several disks, uses a compression method other than stored or deflate, or whose local header name differs from its central directory name, and a tar archive with a global extended header or a sparse entry. A host SHALL refuse an entry name that is not valid UTF-8 with `package.archive_format`.

#### Scenario: An encrypted ZIP archive
- **WHEN** a package archive is a ZIP file with an encrypted entry
- **THEN** the host refuses it with `package.archive_format` and unpacks nothing

### Requirement: The descriptor, record and lock carry the archive digest and the tree digest
The artifact's `sha256` SHALL be the SHA-256 of the archive's bytes. `package.treeSha256` SHALL be the tree digest. The index record and the catalog entry of a package SHALL carry the artifact's `package` member unchanged, and the extension lock SHALL record the artifact digest and the `package` member unchanged.

#### Scenario: A lock records both digests
- **WHEN** a host installs the F# frontend package
- **THEN** its extension lock records the archive's SHA-256 as the artifact digest and the descriptor's `package` member, including `treeSha256`

### Requirement: The tree manifest is canonical text
The tree manifest SHALL be UTF-8 text: the line `morphir-package-tree 1`, then one line per file in ascending order of the UTF-8 bytes of its tree path. Each file line SHALL be its kind (`x` for executable, `f` otherwise), its size in decimal without leading zeros, its SHA-256 in lowercase hexadecimal and its tree path, separated by one space. Every line SHALL end with one LF.

#### Scenario: A two-file tree
- **WHEN** a tree holds `run` (5 bytes, executable) and `lib/a.dll` (3 bytes)
- **THEN** its manifest is `morphir-package-tree 1`, then `f 3 <sha256 of a.dll> lib/a.dll`, then `x 5 <sha256 of run> run`, each followed by LF

### Requirement: The tree digest covers paths, bytes and executable flags only
A file's kind SHALL be `x` when its tree path is the entry point or is listed in `package.executables`, and `f` otherwise. A file's SHA-256 SHALL be computed over its bytes as stored in the archive after decompression, with line endings and encodings untouched. No owner, group, timestamp, permission bit or extended attribute from the archive SHALL affect the manifest.

#### Scenario: Archive metadata does not change the digest
- **WHEN** two archives hold the same files with the same tree paths and bytes, one with Unix mode `0644` and new timestamps, the other with mode `0755` and old timestamps
- **THEN** both give the same tree digest for the same `entryPoint` and `executables`

### Requirement: A declared root strips one directory prefix
When `package.root` is present, it SHALL be a tree path naming a directory. Every file entry SHALL lie under it, and its tree path is its archive path without the root and the following `/`. A directory entry for the root or one of its ancestors is allowed. Any other entry outside the root SHALL be refused with `package.outside_root`.

#### Scenario: A file outside the declared root
- **WHEN** a package with `root` `fsharp-frontend` holds `fsharp-frontend/morphir-fsharp-frontend.exe` and `README.txt`
- **THEN** the host refuses the archive with `package.outside_root`, naming `README.txt`

### Requirement: Only regular files and directories are unpacked
A host SHALL refuse a symbolic link or hard link entry with `package.link_entry`, and a device, FIFO, socket or other non-regular entry with `package.special_entry`. A directory entry SHALL carry no bytes and SHALL create no file. A host SHALL NOT create a directory that holds no file of the tree.

#### Scenario: A symbolic link in a tar archive
- **WHEN** a `tar.gz` package holds a symbolic link `lib/current` to `lib/1.0`
- **THEN** the host refuses the archive with `package.link_entry`

#### Scenario: A device entry
- **WHEN** a `tar.gz` package holds a character device entry
- **THEN** the host refuses the archive with `package.special_entry`

### Requirement: Entry paths are relative, forward-slash and non-traversing
A host SHALL refuse an entry path that contains `\` with `package.backslash`, starts with `/` with `package.absolute_path`, has a first component of a letter followed by `:` with `package.drive_letter`, has an empty or `.` component with `package.empty_or_dot_component`, or has a `..` component with `package.parent_component`. One trailing `/` on a directory entry is not an empty component.

#### Scenario: Traversing and absolute paths
- **WHEN** archives hold the entries `../evil.dll`, `/etc/passwd`, `C:/x.dll`, `a\b.dll` and `a//b.dll`
- **THEN** the host refuses them with `package.parent_component`, `package.absolute_path`, `package.drive_letter`, `package.backslash` and `package.empty_or_dot_component`

### Requirement: Entry path components are portable names
A host SHALL refuse a component that contains a control character (U+0000 to U+001F, U+007F), U+2028, U+2029 or one of `< > : " | ? *` with `package.reserved_character`, a component that ends in `.` or a space with `package.trailing_dot_or_space`, and a component that is a Windows device name, as the toolchain contracts define one for target paths, with `package.device_name`.

#### Scenario: Windows names that cannot be stored
- **WHEN** archives hold the entries `lib/CON.dll`, `com1`, `notes.`, `notes ` and `lib/a:b`
- **THEN** the host refuses them with `package.device_name`, `package.device_name`, `package.trailing_dot_or_space`, `package.trailing_dot_or_space` and `package.reserved_character`

### Requirement: Entry paths are NFC under Unicode 17.0.0
An entry path SHALL be in Unicode Normalization Form C as Unicode 17.0.0 defines it, the version the toolchain contracts pin. A host SHALL refuse a path that is not with `package.not_nfc`, and SHALL use normalization data of that version that it ships, not the operating system's.

#### Scenario: A decomposed name
- **WHEN** an archive holds `notes/cafe\u0301.txt`, with `e` followed by U+0301
- **THEN** the host refuses it with `package.not_nfc`

#### Scenario: A composed non-ASCII name
- **WHEN** an archive holds `notes/caf\u00e9.txt`
- **THEN** the host accepts the name

### Requirement: Entry paths are bounded
An archive entry path SHALL have at most 512 UTF-8 bytes and 240 UTF-16 code units, and each component at most 255 of each. A tree path SHALL have at most 120 UTF-16 code units and 16 components. A host SHALL refuse a longer entry path or tree path with `package.path_length`, and a deeper one with `package.nesting_depth`.

#### Scenario: A tree path one past the limit
- **WHEN** an archive holds a file whose tree path has 121 UTF-16 code units, and another whose tree path has 17 components
- **THEN** the host refuses them with `package.path_length` and `package.nesting_depth`

### Requirement: No two entries share a name on any first-delivery file system
A host SHALL refuse an entry whose path equals an earlier entry's with `package.duplicate_entry`, a file whose path is an earlier entry's directory, or a directory whose path is an earlier file's, with `package.file_directory_conflict`, and an entry with a path prefix whose collision key equals that of a different earlier prefix with `package.case_collision`.

#### Scenario: Case and file-directory collisions
- **WHEN** archives hold `lib/A.dll` then `lib/a.dll`, `lib/x.dll` then `lib/x.dll/y`, and `run` twice
- **THEN** the host refuses them with `package.case_collision`, `package.file_directory_conflict` and `package.duplicate_entry`

### Requirement: Collision keys fold case two ways
Each path prefix SHALL have two collision keys under Unicode 17.0.0: the NFC of its full case folding (statuses C and F of CaseFolding.txt), and the NFC of its full uppercase mapping without language-specific rules. Two prefixes collide when either key is equal.

#### Scenario: A dotless i collides with an i
- **WHEN** an archive holds `lib/\u0131.dll` (dotless i) and `lib/i.dll`
- **THEN** the host refuses the second with `package.case_collision`, because both uppercase to `LIB/I.DLL`

#### Scenario: A sharp s collides with ss
- **WHEN** an archive holds `stra\u00dfe.txt` and `strasse.txt`
- **THEN** the host refuses the second with `package.case_collision`, because both case-fold to `strasse.txt`

### Requirement: Archive size, entry count and unpacked size are bounded
A host SHALL refuse an archive over 256 MiB with `package.archive_too_large` before reading it, more than 4096 entries with `package.entry_count`, more than 4096 files with `package.file_count`, a file over 256 MiB with `package.file_too_large`, and more than 1 GiB of file bytes in total with `package.unpacked_size`. Sizes SHALL be counted as bytes are decompressed, not taken from headers.

#### Scenario: A decompression bomb
- **WHEN** a 1 MiB archive's entries decompress to more than 1 GiB
- **THEN** the host stops decompressing at the limit, refuses the archive with `package.unpacked_size`, and removes what it wrote

### Requirement: The entry point and executables exist in the tree
A host SHALL refuse a package whose `entryPoint` is not the tree path of a file with `package.entry_point_missing`, and one with a path in `executables` that is not the tree path of a file with `package.executable_missing`. For a platform whose target triple contains `-windows-`, the entry point's last component SHALL end in `.exe`, compared ignoring ASCII case; otherwise the host SHALL refuse it with `package.entry_point_not_exe`.

#### Scenario: A Windows entry point that is not an executable
- **WHEN** a package for `x86_64-pc-windows-msvc` has `entryPoint` `run.cmd`
- **THEN** the host refuses it with `package.entry_point_not_exe`

### Requirement: Refusals follow a fixed order
A host SHALL check a package in this order and report only the first refusal: `package.archive_too_large`, `package.archive_digest_mismatch` and `package.archive_format`; then each entry in archive order under the entry rule order; then `package.entry_point_missing`, `package.entry_point_not_exe` and `package.executable_missing`; then `package.tree_digest_mismatch`; then `package.install_path_too_long`. Shared cases SHALL record the code and the entry path it names.

#### Scenario: A bad archive is refused before its entries
- **WHEN** a package's archive does not match its `sha256` and also holds the entry `../x`
- **THEN** the host refuses it with `package.archive_digest_mismatch`

### Requirement: Entry rules are checked in a fixed order
For each entry a host SHALL apply the rules in this order: `entry_count`, `link_entry`, `special_entry`, `backslash`, `absolute_path`, `drive_letter`, `empty_or_dot_component`, `parent_component`, `reserved_character`, `trailing_dot_or_space`, `device_name`, `not_nfc`, `path_length`, `nesting_depth`, `outside_root`, `duplicate_entry`, `file_directory_conflict`, `case_collision`, `file_too_large`, `unpacked_size`, `file_count`, each code prefixed with `package.`.

#### Scenario: An entry that breaks two rules
- **WHEN** an archive holds the entry `../CON`
- **THEN** the host refuses it with `package.parent_component`, not `package.device_name`

### Requirement: A package is verified before it is published
A host SHALL treat a package as verified when the archive's SHA-256 equals the artifact's `sha256`, no rule refuses it, and the tree digest it computes from the bytes it writes equals `package.treeSha256`. It SHALL refuse a different archive digest with `package.archive_digest_mismatch` and a different tree digest with `package.tree_digest_mismatch`. A package that is not verified SHALL NOT be published, recorded or started.

#### Scenario: A wrong tree digest
- **WHEN** a package's archive matches its `sha256` but its files give another tree digest than `package.treeSha256`
- **THEN** the host refuses it with `package.tree_digest_mismatch` and publishes nothing

### Requirement: A published package is stored by its tree digest
A host SHALL publish a verified package at `store/extensions/packages/sha256/<treeSha256>/`, holding the tree manifest as `manifest` and the files under `tree/`. A published package SHALL NOT be changed. On Unix a host SHALL give `x` files mode `0755`, `f` files mode `0644` and directories mode `0755`, and SHALL set no other permission bit.

#### Scenario: The F# frontend in the store
- **WHEN** a host publishes the F# frontend package
- **THEN** `store/extensions/packages/sha256/<treeSha256>/tree/morphir-fsharp-frontend.exe` and the other 238 files exist, and `manifest` holds the tree manifest

### Requirement: A package is staged, verified, then published by one rename
A host SHALL unpack into a new directory `store/extensions/packages/.stage-<random>/`, verify it there, then rename it to its published path. It SHALL hold an exclusive lock on the staging directory's `owner` file while it works. When the published path already exists, the host SHALL verify the existing tree in full and use it if it matches, and otherwise move it aside and publish its own.

#### Scenario: An interrupted unpack is never selected
- **WHEN** a host stops while unpacking the F# frontend
- **THEN** only a `.stage-` directory exists, no lock or catalog entry names the package, and no host selects it

### Requirement: A package is recorded only after it is published
A host SHALL write a package's extension lock and catalog entry, through the transaction journal and under the state lock, only after its tree is published. Recovery SHALL leave a published tree that no lock names in place for collection, and SHALL remove a `.stage-` directory only when it can take that directory's `owner` lock.

#### Scenario: Interrupted after publication
- **WHEN** a host has renamed the staged tree to its published path and stops before writing the lock
- **THEN** the next install of the same package finds and verifies the published tree and records it, and no lock names it until then

### Requirement: A host starts a package's entry point from the store
A host SHALL start a package by the absolute path of its entry point under `store/extensions/packages/sha256/<treeSha256>/tree/`, in the platform's native spelling without a verbatim prefix. The argument vector SHALL be that path followed by the locked arguments. The working directory SHALL be the project directory for a project command, otherwise a new private directory outside the store.

#### Scenario: Starting the F# frontend
- **WHEN** the Native AOT host activates the F# frontend for a project compile on Windows
- **THEN** it starts `<home>\store\extensions\packages\sha256\<treeSha256>\tree\morphir-fsharp-frontend.exe` with the locked arguments, in the project directory

### Requirement: Activation checks the published tree
Provisional on open question `Q-VERIFY`; this is outcome `VERIFY-B`. Before starting a package, a host SHALL check under the state lock that the lock and catalog agree on `package`, that the SHA-256 of `manifest` equals `treeSha256`, and that `tree/` holds exactly the manifest's files as regular files, with the manifest's sizes and, on Unix, executable bits. Under `VERIFY-A` it SHALL also rehash every file.

#### Scenario: A file is missing
- **WHEN** a file listed in the F# frontend's manifest has been deleted from the store
- **THEN** activation refuses with `package.tree_changed` and starts nothing

### Requirement: A full verification is available on request
A host SHALL verify every file of an installed package against its manifest when it installs the package and when the user asks it to verify installed extensions. A failure SHALL be reported with `package.tree_changed`, naming the file.

#### Scenario: A changed byte is found on request
- **WHEN** one byte of an F# frontend assembly in the store has changed and the user asks the host to verify installed extensions
- **THEN** the host reports `package.tree_changed` and names the file

### Requirement: Windows install paths fit the process API
On Windows, a host SHALL refuse to publish a package when the absolute path of any of its files in the store exceeds 259 UTF-16 code units, with `package.install_path_too_long`, naming the longest path and its length.

#### Scenario: A deep home on Windows
- **WHEN** `MORPHIR_HOME` is so long that the F# frontend's longest store path would have 270 UTF-16 code units
- **THEN** the host refuses the install with `package.install_path_too_long` before it publishes anything

### Requirement: A running package holds a lease
A host SHALL hold a shared lock on the package's `lease` file, `store/extensions/packages/sha256/<treeSha256>/lease`, from activation until the started process has exited. It SHALL take the lease while it holds the state lock. The lock SHALL be `flock` with `LOCK_SH` on Unix and `LockFileEx` without `LOCKFILE_EXCLUSIVE_LOCK` over the full range on Windows.

#### Scenario: Two sessions share a package
- **WHEN** two compiles run the F# frontend at the same time
- **THEN** both hold a shared lease on the same `lease` file and neither blocks the other

### Requirement: Uninstall does not delete a package
Uninstalling or updating an extension SHALL remove or replace its lock and catalog entry and SHALL NOT delete or change any published package.

#### Scenario: Uninstall while running
- **WHEN** a user uninstalls the F# frontend while a compile is running it
- **THEN** the lock and catalog entry are removed, the running process continues, and its files stay in the store

### Requirement: Collection removes only unused packages
A host SHALL delete a published package only on an explicit collection command, under the state lock, when no extension lock in the home names its tree digest and it can take an exclusive lock on its `lease` without waiting. It SHALL first rename the package to `.trash-<random>` in the same directory, then delete it.

#### Scenario: A package in use is kept
- **WHEN** collection runs while a process started from an unreferenced package still holds its lease
- **THEN** collection leaves that package in place and reports it as in use

### Requirement: A package grants no trust
A package SHALL NOT change who is trusted. A host MAY conclude from a verified package that its tree is the one the descriptor names, and so, when the descriptor is authenticated, the one its publisher released. A host SHALL NOT conclude publisher identity from unpacking, SHALL NOT treat code signatures inside the tree as authentication, and SHALL still decide claims by the probe.

#### Scenario: A signed executable inside an unsigned release
- **WHEN** a package from an unauthenticated local repository holds an entry point with a valid Authenticode signature
- **THEN** the host treats the release as unauthenticated developer content, and the signature grants nothing

### Requirement: A host that cannot install packages refuses them
A host that reads the package drafts but does not install packages SHALL refuse a package artifact with `package.unsupported`, naming the artifact, and SHALL NOT store or start its archive as a single file.

#### Scenario: A host without package support
- **WHEN** a host without package support selects the F# frontend's package artifact
- **THEN** it refuses with `package.unsupported` and installs nothing

### Requirement: Hosts prove the package rules against shared cases
The package rules SHALL be published as language-neutral cases: valid packages in both formats, one case for each refusal code, tree manifests with their expected digests, and a single-file artifact that stays unchanged. Every host that installs packages SHALL run them and report the expected code and entry path for each. Leases and the Windows path limit SHALL be proved by tests, not data cases.

#### Scenario: Two hosts agree on every case
- **WHEN** the .NET host and the MoonBit host run the shared package cases
- **THEN** both report the expected outcome for every case
