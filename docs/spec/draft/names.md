---
title: "Naming"
description: "Specification for names and paths in Morphir IR v4"
---

# Naming

Morphir's naming system is independent of any specific naming convention (camelCase, snake_case, etc.). This allows the same IR to be rendered in different conventions for different platforms.

IR v4 introduces a **canonical string serialization** for names, paths, and fully-qualified names, making them easier to read and use as keys in JSON objects.

:::info Encoding change
v4 marks an initialism with an uppercase segment (`value-in-USD`) and projects names onto the document tree through a
defined escape (`value-in-_usd.value.json`). This replaces the earlier draft, which fragmented an initialism into
single-letter words and wrapped the run in parentheses (`value-in-(usd)`). The reasoning, including the alternatives
rejected, is recorded in Decision Record 0001 at
`kb/bundles/morphir/morphir-ir/decisions/0001-name-canonicalization-and-initialism-encoding.md`. The full rationale
and the schema patches are in [IR v4 name canonicalization and initialism encoding](../../design/proposals/ir-v4-name-encoding.md).
:::

## Name

A **Name** is a non-empty sequence of **segments**. A segment is a lowercase alphanumeric token that is either an
ordinary word or an initialism.

```text
Name     = NonEmpty[Segment]
Segment  = Word(text) | Initialism(text)
text     = [a-z0-9]+          ; stored lowercase
```

Marking an initialism as a property of a word, rather than fragmenting it into single letters, is what keeps
rendering a backend decision. A Go backend renders `HTMLParser` and a Rust backend renders `HtmlParser` from the same
IR.

- **Canonical Serialization**: segments joined by `-`, with an initialism written in uppercase (e.g. `"user-account"`, `"value-in-USD"`).
- **Legacy Decoding**: the legacy array format (e.g. `["value", "in", "u", "s", "d"]`) decodes by collapsing each maximal run of two or more single-letter words into one initialism. A run of one stays a word.
- **Purpose**: the atomic unit for all identifiers.

### Grammar

```abnf
name       = segment *( "-" segment )
segment    = word / initialism
word       = 1*( LOWER / DIGIT )
initialism = 1*( UPPER / DIGIT )

LOWER      = %x61-7A   ; a-z
UPPER      = %x41-5A   ; A-Z
DIGIT      = %x30-39   ; 0-9
```

A segment is either all lowercase or all uppercase, with digits permitted in both. A mixed-case segment such as
`Usd` is **invalid**, so a casing typo is rejected rather than admitted as a third spelling. A segment made only of
digits matches both productions and is classified as a **word**.

Pattern:

```text
^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$
```

### Initialism handling

| Segments | Canonical | camelCase | PascalCase (Go) | PascalCase (Rust) | snake_case |
|----------|-----------|-----------|-----------------|-------------------|------------|
| `value`, `in`, initialism `usd` | `value-in-USD` | `valueInUSD` | `ValueInUSD` | `ValueInUsd` | `value_in_usd` |
| `value`, `in`, `usd` | `value-in-usd` | `valueInUsd` | `ValueInUsd` | `ValueInUsd` | `value_in_usd` |
| `morphir`, initialism `sdk` | `morphir-SDK` | `morphirSDK` | `MorphirSDK` | `MorphirSdk` | `morphir_sdk` |
| `get`, initialism `html` | `get-HTML` | `getHTML` | `GetHTML` | `GetHtml` | `get_html` |
| initialism `io`, `error` | `IO-error` | `ioError` | `IOError` | `IoError` | `io_error` |

Two rules a backend needs:

- **A leading initialism is lowercased whole in camelCase.** `IO-error` renders `ioError`, not `iOError`.
- **Rendering into a case-free convention is not injective.** `value-in-usd` and `value-in-USD` both render
  `value_in_usd`. Backends must detect collisions after case transformation and report them.

**Note**: `usd` is the word "usd" and renders as `Usd` in PascalCase. `USD` is the initialism and renders as `USD`
or `Usd` depending on the target convention. They are distinct names.

### Document tree projection

A name is not written to a document tree verbatim. It is projected through a reversible escape, because:

1. Case-insensitive filesystems (Windows NTFS, macOS APFS by default) cannot hold both `value-in-USD` and `value-in-usd`.
2. Windows reserves `con`, `prn`, `aux`, `nul`, `com0`-`com9` and `lpt0`-`lpt9` as device names, with any extension.
3. The default Windows `MAX_PATH` of 260 characters is reachable from nested modules plus long names plus `.value.json`.

An initialism segment carries a `_` prefix. A stem colliding with a reserved device name carries a `_` suffix. Every
escaped stem is entirely lowercase, matching `^_?[a-z0-9]+(-_?[a-z0-9]+)*_?$`.

| Canonical name | Filename stem | Type file |
|----------------|---------------|-----------|
| `user` | `user` | `user.type.json` |
| `user-ID` | `user-_id` | `user-_id.type.json` |
| `value-in-USD` | `value-in-_usd` | `value-in-_usd.value.json` |
| `aux` | `aux_` | `aux_.type.json` |
| `CON` | `_con` | `_con.type.json` |

The escape applies to every path segment, not only leaf names: a module directory named `aux` is as unopenable as a
file named `aux.type.json`. Within one module, the escaped stems of all types must be unique, and likewise for
values. Because the escape is injective and its output is all lowercase, satisfying that rule guarantees a tree
written on Linux checks out on Windows and macOS.

### Path length

When a path would exceed the **path budget** measured from the distribution root, the stem is truncated and suffixed
with `__` followed by the first 8 hex digits of the SHA-256 of the untruncated stem. A truncated name is not
recoverable from its filename, so the module's `module.json` must then carry a `fileNames` map from canonical name
to filename stem.

The budget is not a single constant, because the limit it protects against is not universal:

| Target | Limit | Default budget |
|--------|-------|----------------|
| Windows without long paths | `MAX_PATH` 260 | 200 |
| Windows with `LongPathsEnabled` | ~32767 | 4000 |
| Linux, macOS | `PATH_MAX` 4096, `NAME_MAX` 255 | 4000, and 200 per segment |

Windows 10 version 1607 and later can lift `MAX_PATH` through the `LongPathsEnabled` registry setting, and a
process must also opt in through its manifest. A writer therefore detects the effective limit rather than assuming
the most restrictive one, and a `pathBudget` setting overrides the detected value.

**A tree is only as portable as the budget it was written with.** Detection is a convenience for local work, not a
property of the format: a tree written on Linux under the 4000 budget can carry paths that a Windows reader without
long paths cannot open, and nothing in the tree itself would say so. So a distribution that used anything other than
the portable 200 budget MUST record it in `manifest.json`:

```json
{
  "formatVersion": 4,
  "distribution": "Library",
  "package": "my-org/my-project",
  "pathBudget": 4000
}
```

A reader that cannot satisfy a recorded budget reports it rather than failing to open files one at a time. Omitting
`pathBudget` means the portable 200, so an unmarked tree is portable by construction. Publishing pipelines should
pin the portable budget explicitly rather than inheriting whatever the build machine detected.

## TypeVariable

A **TypeVariable** is a semantically distinct wrapper around a Name, used for type parameters.

- **Structure**: Wraps a `Name` to distinguish type variables from value names at the type level
- **Canonical Serialization**: Same as Name (e.g., `"a"`, `"comparable"`)
- **Purpose**: Prevents mixing type variable names with value names in type-safe implementations

A single-letter type parameter is the word `a` and serializes as `"a"`. It is not an initialism, which is why legacy
decoding collapses only runs of two or more single letters.

## Path

A **Path** represents a hierarchical namespace composed of Names.

- **Canonical Serialization**: Names joined by forward slashes (e.g., `"main/domain"`, `"morphir/SDK"`).
- **Legacy Decoding**: Supports array of name arrays (e.g. `[["morphir"], ["s", "d", "k"]]` for `morphir/SDK`).
- **Purpose**: Forms the basis for package and module identification

## PackageName

A **PackageName** identifies a package, the top-level namespace for a Morphir project.

- **Structure**: A `Path` representing the package identity
- **Canonical Serialization**: Same as Path (e.g., `"morphir/SDK"`, `"my-org/my-project"`)
- **Examples**:
  - `morphir/SDK` - The Morphir SDK package
  - `my-org/finance` - A custom organization's finance package
- **Purpose**: Uniquely identifies a package in the ecosystem

## ModuleName

A **ModuleName** identifies a module within a package, combining the package path and module path.

- **Structure**: Composed of a `PackageName` and a module `Path`
- **Canonical Serialization**: Package path followed by module path segments (e.g., `"morphir/SDK/list"`, `"my-org/finance/pricing/models"`)
- **Purpose**: Provides the full path to a module for resolution

## Qualified Name (QName)

A **Qualified Name** uniquely identifies a type or value within a package (relative to that package).

- **Canonical Serialization**: `{module-path}#{local-name}` (e.g., `"main/orders#create-order"`).
- **Components**:
  - Module path: The `Path` to the module within the package
  - Local name: The `Name` of the type or value within that module
- **Purpose**: Identifies items relative to a package context

## Fully-Qualified Name (FQName)

A **Fully-Qualified Name** provides a globally unique identifier for any type or value.

- **Canonical Serialization**: `{package-path}:{module-path}#{local-name}` (e.g., `"morphir/SDK:list#map"`).
- **Legacy Decoding**: Supports array format `[packagePath, modulePath, localName]`.
- **Components**:
  - Package path: The `PackageName` (`Path`)
  - Module path: The module `Path` within the package
  - Local name: The `Name` of the type or value
- **Purpose**: Enables unambiguous references across package boundaries

## URI and Locator (v4)

IR v4 introduces protocol-level addressing for the Document Tree virtual filesystem.

### Scheme

Identifies the type of resource being addressed:

- **Pkg**: `morphir://pkg/...` - Local project resources
- **Deps**: `morphir://deps/...` - External dependency resources
- **Session**: `morphir://session/...` - Transaction state resources

### Suffix

Indicates the content type of a Document Tree node:

- **TypeSuffix**: `.type.json` - Type definition or specification
- **ValueSuffix**: `.value.json` - Value definition or specification
- **ModuleSuffix**: `module.json` - Module manifest

### URI

A protocol-level address combining scheme, path, name, and suffix.

- **Structure**: `Uri(scheme, path, name, suffix)`
- **Example**: `morphir://pkg/my-org/project/main/domain/user.type.json`

A URI addresses the document tree, so its path and name components hold **escaped stems**, not canonical names.
`Uri.name` is therefore a file stem rather than a `Name`.

### Locator

A hybrid identifier that can reference IR entities by either pure identity or protocol address.

- **ByIdentity**: References via `FQName`, using canonical names (e.g., `morphir/SDK:list#map`)
- **ByUri**: References via `URI`, using escaped stems (e.g., `morphir://pkg/.../list/value-in-_usd.value.json`)
- **Purpose**: Bridges semantic IR identity with physical Document Tree addressing

## Conformance

The [name-encoding conformance corpus](../ir/fixtures/naming-conformance.json) records the expected canonical string,
escaped filename stem, rendered forms and legacy array decoding for every case above. Implementations run it rather
than reimplementing the expectations.
