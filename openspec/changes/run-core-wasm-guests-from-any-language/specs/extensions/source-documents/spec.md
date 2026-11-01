# Spec Delta

## Purpose

Defines how `morphir extension compile` turns a source file or a source directory into the documents of one MEP
compile request, so that a multi-module project in any claimed language reaches the guest as one bounded tree.

## ADDED Requirements

### Requirement: Directory input
`compile` SHALL accept a directory as its input. The CLI SHALL walk it and include each regular file whose name
ends with a file extension that the selected language claims. Apart from these, it SHALL read only ignore files and
Git configuration. The walk SHALL skip every hidden directory (a name that starts with `.`) and `.git`,
`.mooncakes`, `_build`, `node_modules` and `.venv`. A tree that gives no document SHALL be refused with
`extension.input_invalid`, exit 2.

#### Scenario: Gleam project tree
- **WHEN** a user compiles `src` that holds `shared/numbers.gleam`, `app/money.gleam`, `app/orders.gleam` and
  `README.md`, with a guest that claims `.gleam`
- **THEN** the request has three documents and `README.md` is not read

#### Scenario: Skipped directories
- **WHEN** a user compiles `src` that holds `app/money.gleam`, `.cache/a.gleam`, `node_modules/x/b.gleam` and
  `_build/c.gleam`
- **THEN** the request has only the document for `app/money.gleam`, and the walk does not list `.cache`,
  `node_modules` or `_build`

#### Scenario: Directory with no claimed files
- **WHEN** a user compiles a directory that has only `.md` files
- **THEN** the command exits 2 with `extension.input_invalid` and no guest starts an operation

### Requirement: Ignore files in the source walk
The walk SHALL honor the ignore files of the selected layers with Git's `gitignore` syntax and nesting rules: a
file's patterns apply below its directory, and `!` includes a path again. The walk SHALL NOT descend into an ignored
directory, read an ignored file or refuse an ignored link or special file. No ignore file SHALL include again a
directory that "Directory input" skips. An ignore file above 1 MiB SHALL be refused with `extension.input_invalid`.

#### Scenario: Ignored build directory
- **WHEN** a user compiles `shop`, a Git work tree that holds a `.gitignore` with the line `/build`,
  `src/app/money.gleam` and `build/packages/gleam_stdlib/src/gleam/list.gleam`
- **THEN** the request has the document for `src/app/money.gleam`, no document from `build`, and the walk does not
  list `build`

#### Scenario: Nested ignore file
- **WHEN** the walked tree is in a Git work tree, `src/app/.gitignore` has the line `generated.gleam`, and the tree
  has `src/app/generated.gleam` and `src/generated.gleam`
- **THEN** `src/app/generated.gleam` is not read and `src/generated.gleam` is a document

#### Scenario: Morphir-only exclusion
- **WHEN** the walked directory holds a `.morphirignore` with the line `test/`, and `test/money_test.gleam` is a
  file that Git tracks
- **THEN** `test/money_test.gleam` is not read

#### Scenario: Ignored link
- **WHEN** the walked directory is in a Git work tree and holds a `.gitignore` with the line `/vendor`, and `vendor`
  is a symbolic link to another directory
- **THEN** the walk does not refuse the link and does not follow it

### Requirement: Precedence of ignore files
When patterns of several ignore files match one path, the last matching pattern SHALL decide. The patterns SHALL
come in this order: the global excludes file, then `.git/info/exclude`, then the ignore files of each directory
from the highest directory that the walk reads down to the deepest. In one directory, the patterns of
`.morphirignore` SHALL come after those of `.gitignore`. As in Git, a path SHALL NOT be included again when a
parent directory of it is excluded.

#### Scenario: Morphir ignore file includes a file again
- **WHEN** the walked directory is in a Git work tree and holds a `.gitignore` with the line `*_gen.gleam` and a
  `.morphirignore` with the line `!src/model_gen.gleam`, and the tree has `src/model_gen.gleam` and
  `src/other_gen.gleam`
- **THEN** `src/model_gen.gleam` is a document and `src/other_gen.gleam` is not read

#### Scenario: Excluded parent directory
- **WHEN** in a Git work tree, a `.gitignore` has the line `gen/` and a `.morphirignore` in the same directory has
  the line `!gen/model.gleam`
- **THEN** `gen/model.gleam` is not read, because its parent directory is excluded

#### Scenario: Deeper directory decides
- **WHEN** in a Git work tree, the root `.morphirignore` has the line `!src/app/money.gleam`, and
  `src/app/.gitignore` has the line `money.gleam`
- **THEN** `src/app/money.gleam` is not read

#### Scenario: Ignore file includes again what the global excludes file excludes
- **WHEN** the global excludes file has the line `*_gen.gleam`, and the root `.gitignore` of the work tree has the
  line `!src/model_gen.gleam`
- **THEN** `src/model_gen.gleam` is a document

### Requirement: Git ignore layers
By default, the walk SHALL read the ignore layers that Git reads. In a Git work tree, these are the global excludes
file (`core.excludesFile`, else `$XDG_CONFIG_HOME/git/ignore`, else `$HOME/.config/git/ignore`),
`.git/info/exclude`, and the `.gitignore` and `.morphirignore` files from the work-tree root down through the
walked tree. A missing file SHALL give no patterns. Outside a work tree, the walk SHALL read only the
`.morphirignore` files in the walked tree.

#### Scenario: Global excludes apply
- **WHEN** the walked tree is in a Git work tree, the user's global excludes file has the line `*_test.gleam`, and
  the tree has `src/app/money.gleam` and `src/app/money_test.gleam`
- **THEN** `src/app/money.gleam` is a document and `src/app/money_test.gleam` is not read

#### Scenario: Repository exclude file applies
- **WHEN** the repository's `.git/info/exclude` has the line `/scratch`, and the user compiles the work-tree root,
  which holds `scratch/try.gleam` and `src/app/money.gleam`
- **THEN** the request has only the document for `src/app/money.gleam`

#### Scenario: Ignore file above the walked directory
- **WHEN** a user compiles `src` in `/work/shop`, a Git work tree whose root `.gitignore` has the line
  `*_gen.gleam`, and the tree has `src/app/money.gleam` and `src/app/model_gen.gleam`
- **THEN** `src/app/model_gen.gleam` is not read

#### Scenario: Outside a Git work tree
- **WHEN** the walked directory is not in a Git work tree and holds a `.gitignore` with the line `test/` and a
  `.morphirignore` with the line `/scratch`
- **THEN** the files under `test` are documents and the files under `scratch` are not read

### Requirement: Ignore layer switches
`compile` SHALL accept `--skip-ignore-layer <layer>`, which the user can give more than once, to turn off one layer
of "Git ignore layers": `global` (the global excludes file), `info-exclude` (`.git/info/exclude`) or `above` (the
ignore files above the walked directory). An unknown layer name SHALL be refused with `extension.input_invalid`,
exit 2, and the message SHALL name the known layers.

#### Scenario: One layer turned off
- **WHEN** the walked tree is in a Git work tree, the global excludes file has the line `*_test.gleam`, and the user
  gives `--skip-ignore-layer global`
- **THEN** each `*_test.gleam` file that the other layers do not ignore is a document

#### Scenario: Unknown layer
- **WHEN** the user gives `--skip-ignore-layer home`
- **THEN** the command exits 2 with `extension.input_invalid`, the message names `global`, `info-exclude` and
  `above`, and no guest starts

### Requirement: Contained ignore mode
`compile` SHALL accept `--ignore-mode <mode>`: `git` (the default, "Git ignore layers") or `contained`. In
contained mode the walk SHALL read only the `.gitignore` and `.morphirignore` files in the walked tree, in or
outside a Git work tree, and no other layer or Git configuration, so the documents depend only on the tree and the
options. An unknown mode SHALL be refused with `extension.input_invalid`, exit 2.

#### Scenario: Global excludes do not apply in contained mode
- **WHEN** the user's global Git excludes file has the line `*.gleam`, the tree has no ignore file, and the user
  gives `--ignore-mode contained`
- **THEN** every `.gleam` file in the tree is a document

#### Scenario: Ignore file above the walked directory in contained mode
- **WHEN** a user compiles `src` with `--ignore-mode contained`, the root `.gitignore` of the work tree has the line
  `*_gen.gleam`, and the tree has `src/app/model_gen.gleam`
- **THEN** `src/app/model_gen.gleam` is a document

#### Scenario: Contained mode outside a Git work tree
- **WHEN** the walked directory is not in a Git work tree and holds a `.gitignore` with the line `test/`, and the
  user gives `--ignore-mode contained`
- **THEN** the files under `test` are not read

### Requirement: Ignore files filter only the walk
Ignore files SHALL filter only the entries below an input directory. A file that the user names as the input SHALL
be read even when an ignore file matches it, and a pattern SHALL NOT exclude the input directory or a directory
above it.

#### Scenario: Named file that an ignore file matches
- **WHEN** a `.gitignore` in the work tree has the line `*_gen.gleam`, and a user compiles `src/model_gen.gleam`
- **THEN** the request has one document for `src/model_gen.gleam`

#### Scenario: Named directory that a pattern above matches
- **WHEN** the root `.gitignore` of a Git work tree has the lines `/gen` and `*_gen.gleam`, and the user compiles
  `gen`, which holds `model.gleam` and `model_gen.gleam`
- **THEN** `gen/model.gleam` is a document, and `gen/model_gen.gleam` is not

### Requirement: Relative document URIs
Each document URI SHALL be the file's path relative to the source base, with `/` separators. The source base
SHALL be `--source-base` when given, else the input directory. The current directory SHALL NOT change the URIs.
The input SHALL be at or below the source base. The request SHALL NOT contain `sources.root` or an absolute host
path.

#### Scenario: Directory input without a source base
- **WHEN** a user compiles `src` and the tree has `src/app/money.gleam`
- **THEN** that document has the URI `app/money.gleam` and the request has no `sources.root`

#### Scenario: Same URIs from any current directory
- **WHEN** a user in `/work/shop` compiles `src` and a user in `/tmp` compiles `/work/shop/src`, both without
  `--source-base`
- **THEN** the two requests have the same URIs

#### Scenario: Module paths of a published extension
- **WHEN** a user in the parent of `generated` compiles `generated/src`, which holds `Acme/Rules/Main.elm`, with
  the Elm extension
- **THEN** that document has the URI `Acme/Rules/Main.elm`, which matches the module `Acme.Rules.Main`

#### Scenario: Explicit source base
- **WHEN** a user compiles `/work/shop/src` with `--source-base /work/shop`
- **THEN** the document has the URI `src/app/money.gleam`

#### Scenario: Input outside the source base
- **WHEN** a user compiles `/other/src` with `--source-base /work/shop`
- **THEN** the command exits 2 with `extension.input_invalid` and the message names the source base

### Requirement: Safe URI segments
Each URI segment SHALL be non-empty and SHALL NOT be `.` or `..`. A segment SHALL be percent-encoded as an RFC 3986
path segment, so that `%`, `?`, `#`, `\`, `:`, spaces, control characters and non-ASCII characters do not appear
raw. Two files that give the same URI SHALL be refused with `extension.input_invalid`.

#### Scenario: File name with a space
- **WHEN** the tree has `src/my module.gleam`
- **THEN** its URI is `src/my%20module.gleam`

#### Scenario: Plain names stay the same
- **WHEN** a file path has only letters, digits, `-`, `.`, `_` and `~` in each segment
- **THEN** its URI equals its relative path

### Requirement: Single file input
A single file input SHALL give one document. Without `--source-base`, its URI SHALL follow the earlier rule: a clean
relative path keeps its nesting, and an absolute path or a path with `..` gives only the file name. With
`--source-base`, the directory rule SHALL apply.

#### Scenario: MoonBit guest and one file
- **WHEN** a user compiles `src/main.mbt` with the MoonBit guest
- **THEN** the request has one document with URI `src/main.mbt` and `languageId: "moonbit"`, as before

### Requirement: Deterministic order
Documents SHALL be sorted by URI in byte order. Two runs over the same tree with the same options and the same
ignore files in every layer that the walk reads SHALL give the same request bytes. With `--ignore-mode contained`,
two runs over the same tree with the same options SHALL give the same request bytes on every machine.

#### Scenario: Same tree twice
- **WHEN** a user compiles the same unchanged tree twice with the same options and unchanged ignore files
- **THEN** the two `compileModel` requests are byte for byte the same

#### Scenario: Two machines in contained mode
- **WHEN** two users with different global excludes files compile copies of the same tree with `--ignore-mode contained` and
  the same options
- **THEN** the two `compileModel` requests are byte for byte the same

### Requirement: Tree limits
The CLI SHALL refuse a tree with more than 1,024 documents, a file larger than 1 MiB, more than 2 MiB of source
bytes in total, a depth of more than 32 directories or more than 16,384 walked entries, with
`extension.input_invalid`, exit 2, and a message that names the limit and its value. The framed request SHALL still
fit in 4 MiB, or the command SHALL fail with `extension.request_limit`. All checks SHALL happen before an operation
session starts.

#### Scenario: Too many documents
- **WHEN** a tree has 1,025 `.gleam` files
- **THEN** the command exits 2 with `extension.input_invalid`, the message names the limit of 1,024 documents,
  and no operation session starts

#### Scenario: Request too large after encoding
- **WHEN** the documents fit in 2 MiB but the framed request is larger than 4 MiB
- **THEN** the command exits 2 with `extension.request_limit`

### Requirement: Links and special files
The walk SHALL NOT follow symbolic links. A symbolic link or a special file anywhere in the tree, unless the walk
skips or ignores it, SHALL be refused with `extension.input_invalid`, and the message SHALL name its relative path.

#### Scenario: Link inside the tree
- **WHEN** `src/vendor` is a symbolic link to another directory
- **THEN** the command exits 2 with `extension.input_invalid` and the message names `src/vendor`

### Requirement: UTF-8 source text
Each included file SHALL be valid UTF-8. A file that is not SHALL be refused with `extension.input_invalid`,
exit 2, and the message SHALL name its URI.

#### Scenario: Latin-1 file
- **WHEN** an included file has bytes that are not valid UTF-8
- **THEN** the command exits 2 with `extension.input_invalid` and the message names the URI of that file

### Requirement: Multi-document permission
A request with more than one document SHALL be sent only when the guest claims `frontend.multiDocument: true`.
Otherwise the command SHALL exit 2 with `extension.capability_unavailable` before the operation session.

#### Scenario: MoonBit guest and a tree
- **WHEN** a user compiles a directory with two `.mbt` files and the MoonBit guest, which does not claim
  multi-document support
- **THEN** the command exits 2 with `extension.capability_unavailable` and no operation session starts

### Requirement: Context digest unchanged
The context digest SHALL stay the SHA-256 of the package name and options. The documents SHALL NOT change it.

#### Scenario: Same options, different trees
- **WHEN** two compiles use the same package and options but different trees
- **THEN** both requests carry the same `contextDigest`
