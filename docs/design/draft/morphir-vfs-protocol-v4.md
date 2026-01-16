---
title: Morphir-VFS & Polyglot Protocol Design (v4)
sidebar_label: VFS Protocol v4
sidebar_position: 1
---

# Morphir-VFS & Polyglot Protocol Design (v4)

| | |
|---|---|
| **Version** | 0.1.0-draft |
| **Date** | 2026-01-15 |
| **Status** | DRAFT |

:::caution
This is a **DRAFT** design document. All types and protocols are subject to change.
:::

## Introduction

### Purpose

This document specifies the "Morphir-VFS" architecture and the JSON-RPC 2.0 protocol for the next generation Morphir toolchain (v4). It enables a polyglot ecosystem where a Core Daemon orchestrates compilation and refactoring across language-agnostic backends.

### Design Principles

- **Immutability First**: All IR transformations are modeled as immutable state transitions.
- **VFS-Centric**: The Morphir Distribution is modeled as a hierarchical file system, accessible to standard shell tools.
- **Graceful Degradation**: Support for "Best Effort" code generation during incremental refactoring.
- **Transactional Integrity**: Multi-module refactors are handled via a Propose-Commit lifecycle.
- **Dual Mode**: Support both classic single-blob distribution and discrete VFS file layout.

### Reference Implementation

All type definitions in this document use **Gleam** syntax as the canonical reference implementation, ensuring functional contracts and sum/product type semantics.

## Architecture Overview

### Hub-and-Spoke Model

```
                    ┌─────────────────────┐
                    │     Core Daemon     │
                    │  (Gleam/Go/Rust)    │
                    │                     │
                    │  ┌───────────────┐  │
                    │  │  VFS Manager  │  │
                    │  └───────────────┘  │
                    │  ┌───────────────┐  │
                    │  │  IR Graph     │  │
                    │  │  (In-Memory)  │  │
                    │  └───────────────┘  │
                    └──────────┬──────────┘
                               │ JSON-RPC 2.0
           ┌───────────────────┼───────────────────┐
           │                   │                   │
           ▼                   ▼                   ▼
    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
    │  TypeScript │     │ Spark/Scala │     │     Go      │
    │   Backend   │     │   Backend   │     │   Backend   │
    └─────────────┘     └─────────────┘     └─────────────┘
```

- **Hub (Core Daemon)**: Language-agnostic daemon that acts as JSON-RPC 2.0 server and VFS orchestrator.
- **Spokes (Backends)**: Polyglot "sidecars" that consume IR via the VFS protocol.
- **Transport**: JSON-RPC 2.0 over HTTP (CLI-to-Daemon) or Stdin/Stdout (LSP/One-shot).

### Dual Distribution Modes

| Mode | Layout | Use Case |
|------|--------|----------|
| **Classic** | Single `morphir-ir.json` blob | Compatibility with existing tooling, simple projects |
| **VFS (Discrete)** | `.morphir-dist/` directory tree | Large projects, shell-tool integration, incremental updates |

## Schema Architecture

The v4 schema specification uses **separate root schemas with shared `$ref` definitions**.

```
schemas/v4/
├── common/                 # Shared $ref definitions
│   ├── naming.yaml             # Path, Name, FQName, Locator
│   ├── types.yaml              # Type expressions & definitions
│   ├── values.yaml             # Value expressions & definitions
│   └── access.yaml             # AccessControlled wrapper
├── classic/                # Single-blob mode
│   └── distribution.yaml       # Root: Distribution
└── vfs/                    # Discrete mode
    ├── format.yaml             # .morphir-dist/format.json
    ├── module.yaml             # module.json schema
    ├── type-node.yaml          # *.type.json schema
    └── value-node.yaml         # *.value.json schema
```

### VFS Granularity

The VFS mode uses **one file per definition**:

- `User.type.json` contains only the `User` type definition
- `login.value.json` contains only the `login` value definition
- `module.json` contains module metadata and exports

## Distribution Structure (.morphir-dist)

```
.morphir-dist/
├── format.json            # Layout metadata and spec version (semver)
├── morphir.toml           # Project-level configuration
├── session.jsonl          # Append-only transaction journal
├── pkg/                   # Local project IR (Namespace-to-Directory)
│   └── my-org/
│       └── my-project/
│           ├── module.json       # Module manifest
│           ├── types/
│           │   └── user.type.json
│           └── values/
│               └── login.value.json
└── deps/                  # Dependency IR (versioned)
    └── morphir/
        └── sdk/
            └── 1.2.0/
                └── ...
```

### VFS File Types

| File | Content | Purpose |
|------|---------|---------|
| `format.json` | Distribution metadata | Layout version, distribution type, package name |
| `module.json` | Module manifest | Lists types and values in the module |
| `*.type.json` | Type definition OR specification | TypeDefinition or TypeSpecification |
| `*.value.json` | Value definition OR specification | ValueDefinition or ValueSpecification |
| `session.jsonl` | Transaction journal | Append-only log for crash recovery |

### VFS File Polymorphism

Type and value files use **mutually exclusive keys** to indicate whether they contain a definition or specification:

```json
// Type file with definition (Library distribution)
{ "formatVersion": "4.0.0", "name": "user", "def": { "TypeAliasDefinition": { ... } } }

// Type file with specification (Specs distribution or dependency)
{ "formatVersion": "4.0.0", "name": "user", "spec": { "TypeAliasSpecification": { ... } } }
```

| Key | Used In | Contains |
|-----|---------|----------|
| `def` | Library (pkg/) | Full implementation (TypeDefinition, ValueDefinition) |
| `spec` | Specs distribution, resolved dependencies | Public interface only (TypeSpecification, ValueSpecification) |

### Format Versioning

All VFS files include a `formatVersion` field using semantic versioning (semver):

- **Major**: Breaking changes to structure or semantics
- **Minor**: Backwards-compatible additions
- **Patch**: Bug fixes, clarifications

Current version: `4.0.0`

### Namespace Mapping Rules

Morphir paths (e.g., `["Main", "Domain"]`) map to physical directories using canonical naming:

1. `pkg/` or `deps/{pkg}/{ver}/` is the root
2. Each path segment is a canonical kebab-case directory (e.g., `main/domain/`)
3. Terminal types are suffixed `.type.json` (e.g., `user.type.json`)
4. Terminal values are suffixed `.value.json` (e.g., `login.value.json`)
5. Every module directory contains a `module.json`

Example: Path `["Main", "Domain"]` → `pkg/main/domain/`

## Gleam Type Definitions

### Naming Module

The naming module uses **newtype wrappers** for type safety, **smart constructors** for validation, and a **canonical string format** for serialization.

#### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Type safety | Newtype wrappers (opaque) | Prevents mixing Name/Path/PackagePath at compile time |
| Internal storage | Canonical string | Optimized for serialization, keys, URLs |
| Abbreviation format | Parentheses `(usd)` | URL-safe, readable, unambiguous |
| Input parsing | Permissive | Accept multiple formats, always output canonical |

#### Canonical String Format

```
Name:    words joined by `-`, abbreviations in `()`    →  value-in-(usd)
Path:    names joined by `/`                           →  main/domain/orders
QName:   {module-path}#{local}                         →  main/domain#user-account
FQName:  {package}:{module}#{local}                    →  morphir/sdk:list#map
```

**Abbreviation handling:** Consecutive single-letter words are grouped in parentheses:

| Structured | Canonical |
|------------|-----------|
| `["value", "in", "u", "s", "d"]` | `value-in-(usd)` |
| `["usd"]` | `usd` |
| `["get", "h", "t", "m", "l"]` | `get-(html)` |
| `["my", "a", "p", "i", "client"]` | `my-(api)-client` |

**Important: Abbreviations require explicit letter-by-letter separation in input.**

Each segment between separators is parsed as a **single word**. To represent an abbreviation (sequence of single letters), you must separate each letter:

| Input Format | Input | Parsed Words | Canonical Output |
|--------------|-------|--------------|------------------|
| snake_case | `in_usd` | `["in", "usd"]` | `in-usd` |
| snake_case | `in_u_s_d` | `["in", "u", "s", "d"]` | `in-(usd)` |
| kebab-case | `in-usd` | `["in", "usd"]` | `in-usd` |
| kebab-case | `in-u-s-d` | `["in", "u", "s", "d"]` | `in-(usd)` |
| camelCase | `inUsd` | `["in", "usd"]` | `in-usd` |
| camelCase | `inUSD` | `["in", "u", "s", "d"]` | `in-(usd)` |
| canonical | `in-(usd)` | `["in", "u", "s", "d"]` | `in-(usd)` |

**Rendering to target conventions:**

| Canonical | Structured | camelCase | PascalCase | snake_case | kebab-case |
|-----------|------------|-----------|------------|------------|------------|
| `in-usd` | `["in", "usd"]` | `inUsd` | `InUsd` | `in_usd` | `in-usd` |
| `in-(usd)` | `["in", "u", "s", "d"]` | `inUSD` | `InUSD` | `in_u_s_d` | `in-u-s-d` |
| `get-(html)` | `["get", "h", "t", "m", "l"]` | `getHTML` | `GetHTML` | `get_h_t_m_l` | `get-h-t-m-l` |
| `my-(api)-client` | `["my", "a", "p", "i", "client"]` | `myAPIClient` | `MyAPIClient` | `my_a_p_i_client` | `my-a-p-i-client` |

This means:
- `usd` = the word "usd" (renders as `Usd` in PascalCase)
- `(usd)` = the abbreviation U-S-D (renders as `USD` in PascalCase)

#### Core Types

```gleam
// === naming.gleam ===

import gleam/list
import gleam/result
import gleam/string

// ============================================================
// NEWTYPES (Opaque for type safety)
// ============================================================

/// A Name is a list of lowercase words, case-agnostic.
/// Stored internally as canonical string for efficiency.
/// Example: "user-account" represents ["user", "account"]
pub opaque type Name {
  Name(canonical: String)
}

/// A Path is a hierarchical namespace (list of Names).
/// Example: "main/domain/orders"
pub opaque type Path {
  Path(canonical: String)
}

/// Type variable name - semantically distinct from value names.
pub opaque type TypeVariable {
  TypeVariable(name: Name)
}

/// Package path - the top-level namespace.
pub opaque type PackagePath {
  PackagePath(path: Path)
}

/// Module path - relative to package.
pub opaque type ModulePath {
  ModulePath(path: Path)
}

// ============================================================
// COMPOUND TYPES
// ============================================================

/// Qualified Name: Module path + local name
pub type QName {
  QName(module_path: ModulePath, local_name: Name)
}

/// Fully-Qualified Name: Package + Module + Local
pub type FQName {
  FQName(
    package_path: PackagePath,
    module_path: ModulePath,
    local_name: Name,
  )
}

/// URI scheme for VFS protocol addressing
pub type Scheme {
  Pkg       // morphir://pkg/...  (local project)
  Deps      // morphir://deps/... (external dependencies)
  Session   // morphir://session/... (transaction state)
}

/// VFS node suffix indicating content type
pub type Suffix {
  TypeSuffix    // .type.json
  ValueSuffix   // .value.json
  ModuleSuffix  // module.json
}

/// Protocol-level URI with scheme
pub type Uri {
  Uri(scheme: Scheme, path: Path, name: Name, suffix: Suffix)
}

/// Hybrid locator: pure IR identity OR protocol address
pub type Locator {
  ByIdentity(fqname: FQName)
  ByUri(uri: Uri)
}

// ============================================================
// VALIDATION ERRORS
// ============================================================

pub type NameError {
  EmptyName
  EmptyWord
  InvalidCharacter(word: String, char: String)
  WordMustBeLowercase(word: String)
}

pub type PathError {
  EmptyPath
  InvalidSegment(index: Int, error: NameError)
}

pub type ParseError {
  InvalidCanonicalName(input: String, reason: String)
  InvalidCanonicalPath(input: String, reason: String)
  InvalidCanonicalQName(input: String, reason: String)
  InvalidCanonicalFQName(input: String, reason: String)
  MissingSeparator(expected: String)
}

// ============================================================
// SMART CONSTRUCTORS (from structured form)
// ============================================================

/// Construct a Name from a list of words, validating each.
/// Consecutive single-letter words are encoded as abbreviations.
pub fn name_from_words(words: List(String)) -> Result(Name, NameError) {
  case words {
    [] -> Error(EmptyName)
    _ -> {
      use validated <- result.try(list.try_map(words, validate_word))
      Ok(Name(encode_words_to_canonical(validated)))
    }
  }
}

/// Construct a Path from a list of Names.
pub fn path_from_names(names: List(Name)) -> Result(Path, PathError) {
  case names {
    [] -> Error(EmptyPath)
    _ -> {
      let canonical =
        names
        |> list.map(name_to_string)
        |> string.join("/")
      Ok(Path(canonical))
    }
  }
}

/// Construct a Path from raw string word lists.
pub fn path_from_word_lists(segments: List(List(String))) -> Result(Path, PathError) {
  case segments {
    [] -> Error(EmptyPath)
    _ -> {
      use names <- result.try(
        list.index_map(segments, fn(words, idx) { #(idx, words) })
        |> list.try_map(fn(pair) {
          let #(idx, words) = pair
          case name_from_words(words) {
            Ok(n) -> Ok(n)
            Error(e) -> Error(InvalidSegment(idx, e))
          }
        })
      )
      path_from_names(names)
    }
  }
}

/// Unsafe constructor for literals - panics on invalid input.
pub fn name_unchecked(words: List(String)) -> Name {
  case name_from_words(words) {
    Ok(n) -> n
    Error(_) -> panic as "Invalid name"
  }
}

// ============================================================
// SMART CONSTRUCTORS (from canonical string - permissive)
// ============================================================

/// Parse a canonical Name string. Accepts multiple formats:
/// - Canonical: "value-in-(usd)"
/// - Plain kebab: "value-in-usd"
/// - camelCase: "valueInUSD" (convenience)
/// - snake_case: "value_in_usd" (convenience)
pub fn name_from_string(s: String) -> Result(Name, ParseError) {
  case string.is_empty(s) {
    True -> Error(InvalidCanonicalName(s, "empty string"))
    False -> {
      // Try canonical format first, then fallback formats
      case parse_canonical_name(s) {
        Ok(n) -> Ok(n)
        Error(_) -> parse_alternative_name_formats(s)
      }
    }
  }
}

/// Parse a canonical Path string.
pub fn path_from_string(s: String) -> Result(Path, ParseError) {
  case string.is_empty(s) {
    True -> Error(InvalidCanonicalPath(s, "empty string"))
    False -> {
      let segments = string.split(s, "/")
      use names <- result.try(
        list.try_map(segments, fn(seg) {
          name_from_string(seg)
          |> result.map_error(fn(_) { InvalidCanonicalPath(s, "invalid segment") })
        })
      )
      case path_from_names(names) {
        Ok(p) -> Ok(p)
        Error(_) -> Error(InvalidCanonicalPath(s, "empty path"))
      }
    }
  }
}

/// Parse a canonical QName string: "module/path#local-name"
pub fn qname_from_string(s: String) -> Result(QName, ParseError) {
  case string.split(s, "#") {
    [mod_str, local_str] -> {
      use mod_path <- result.try(path_from_string(mod_str))
      use local <- result.try(name_from_string(local_str))
      Ok(QName(module_path(mod_path), local))
    }
    _ -> Error(InvalidCanonicalQName(s, "expected format: module/path#local-name"))
  }
}

/// Parse a canonical FQName string: "package/path:module/path#local-name"
pub fn fqname_from_string(s: String) -> Result(FQName, ParseError) {
  case string.split(s, ":") {
    [pkg_str, rest] -> {
      case string.split(rest, "#") {
        [mod_str, local_str] -> {
          use pkg <- result.try(path_from_string(pkg_str))
          use mod <- result.try(path_from_string(mod_str))
          use local <- result.try(name_from_string(local_str))
          Ok(FQName(package_path(pkg), module_path(mod), local))
        }
        _ -> Error(InvalidCanonicalFQName(s, "missing # separator"))
      }
    }
    _ -> Error(InvalidCanonicalFQName(s, "missing : separator"))
  }
}

// ============================================================
// ACCESSORS (to canonical string - always canonical output)
// ============================================================

/// Get the canonical string representation of a Name.
pub fn name_to_string(n: Name) -> String {
  let Name(canonical) = n
  canonical
}

/// Get the canonical string representation of a Path.
pub fn path_to_string(p: Path) -> String {
  let Path(canonical) = p
  canonical
}

/// Get the canonical string representation of a QName.
pub fn qname_to_string(qn: QName) -> String {
  let QName(mod_path, local) = qn
  module_path_to_string(mod_path) <> "#" <> name_to_string(local)
}

/// Get the canonical string representation of an FQName.
pub fn fqname_to_string(fqn: FQName) -> String {
  let FQName(pkg, mod, local) = fqn
  package_path_to_string(pkg) <> ":" <> module_path_to_string(mod) <> "#" <> name_to_string(local)
}

fn package_path_to_string(pp: PackagePath) -> String {
  let PackagePath(p) = pp
  path_to_string(p)
}

fn module_path_to_string(mp: ModulePath) -> String {
  let ModulePath(p) = mp
  path_to_string(p)
}

// ============================================================
// ACCESSORS (to structured form - computed from canonical)
// ============================================================

/// Get the words from a Name (computed by parsing canonical).
pub fn name_to_words(n: Name) -> List(String) {
  let Name(canonical) = n
  decode_canonical_to_words(canonical)
}

/// Get the segments from a Path (computed by parsing canonical).
pub fn path_to_names(p: Path) -> List(Name) {
  let Path(canonical) = p
  canonical
  |> string.split("/")
  |> list.filter_map(fn(s) {
    case name_from_string(s) {
      Ok(n) -> Ok(n)
      Error(_) -> Error(Nil)
    }
  })
}

// ============================================================
// WRAPPER CONSTRUCTORS
// ============================================================

pub fn type_variable(n: Name) -> TypeVariable {
  TypeVariable(n)
}

pub fn type_variable_name(tv: TypeVariable) -> Name {
  let TypeVariable(n) = tv
  n
}

pub fn package_path(p: Path) -> PackagePath {
  PackagePath(p)
}

pub fn module_path(p: Path) -> ModulePath {
  ModulePath(p)
}

// ============================================================
// INTERNAL HELPERS
// ============================================================

fn validate_word(word: String) -> Result(String, NameError) {
  case string.is_empty(word) {
    True -> Error(EmptyWord)
    False -> {
      let lower = string.lowercase(word)
      case word == lower {
        False -> Error(WordMustBeLowercase(word))
        True -> {
          let valid_chars = "abcdefghijklmnopqrstuvwxyz0123456789"
          let chars = string.to_graphemes(word)
          case list.all(chars, fn(c) { string.contains(valid_chars, c) }) {
            True -> Ok(word)
            False -> Error(InvalidCharacter(word, "non-alphanumeric"))
          }
        }
      }
    }
  }
}

/// Encode words to canonical format, grouping consecutive single letters.
fn encode_words_to_canonical(words: List(String)) -> String {
  words
  |> group_consecutive_singles
  |> list.map(fn(segment) {
    case segment {
      SingleLetters(letters) -> "(" <> string.join(letters, "") <> ")"
      MultiLetterWord(word) -> word
    }
  })
  |> string.join("-")
}

type WordSegment {
  SingleLetters(List(String))
  MultiLetterWord(String)
}

fn group_consecutive_singles(words: List(String)) -> List(WordSegment) {
  // Groups consecutive single-letter words into SingleLetters segments
  // ["value", "in", "u", "s", "d"] -> [MultiLetterWord("value"), MultiLetterWord("in"), SingleLetters(["u", "s", "d"])]
  do_group_consecutive_singles(words, [], [])
}

fn do_group_consecutive_singles(
  words: List(String),
  current_singles: List(String),
  acc: List(WordSegment),
) -> List(WordSegment) {
  case words {
    [] -> {
      case current_singles {
        [] -> list.reverse(acc)
        singles -> list.reverse([SingleLetters(list.reverse(singles)), ..acc])
      }
    }
    [word, ..rest] -> {
      case string.length(word) {
        1 -> {
          // Single letter - accumulate
          do_group_consecutive_singles(rest, [word, ..current_singles], acc)
        }
        _ -> {
          // Multi-letter word - flush any accumulated singles first
          let new_acc = case current_singles {
            [] -> [MultiLetterWord(word), ..acc]
            singles -> [MultiLetterWord(word), SingleLetters(list.reverse(singles)), ..acc]
          }
          do_group_consecutive_singles(rest, [], new_acc)
        }
      }
    }
  }
}

/// Decode canonical format back to word list.
fn decode_canonical_to_words(canonical: String) -> List(String) {
  canonical
  |> string.split("-")
  |> list.flat_map(fn(segment) {
    case string.starts_with(segment, "(") && string.ends_with(segment, ")") {
      True -> {
        // Abbreviation: "(usd)" -> ["u", "s", "d"]
        segment
        |> string.drop_start(1)
        |> string.drop_end(1)
        |> string.to_graphemes
      }
      False -> [segment]
    }
  })
}

fn parse_canonical_name(s: String) -> Result(Name, ParseError) {
  // Parse canonical format with potential abbreviations
  let words = decode_canonical_to_words(s)
  case list.all(words, fn(w) { result.is_ok(validate_word(w)) }) {
    True -> Ok(Name(s))
    False -> Error(InvalidCanonicalName(s, "invalid word"))
  }
}

fn parse_alternative_name_formats(s: String) -> Result(Name, ParseError) {
  // Try camelCase, snake_case, etc.
  // This is a simplified implementation - production would be more robust
  let words = case string.contains(s, "_") {
    True -> string.split(s, "_")  // snake_case
    False -> split_camel_case(s)   // camelCase/PascalCase
  }
  case name_from_words(list.map(words, string.lowercase)) {
    Ok(n) -> Ok(n)
    Error(_) -> Error(InvalidCanonicalName(s, "unrecognized format"))
  }
}

fn split_camel_case(s: String) -> List(String) {
  // Simplified camelCase splitter
  // "valueInUSD" -> ["value", "In", "U", "S", "D"]
  // Production implementation would handle edge cases better
  [s]  // Placeholder - real implementation needed
}
```

#### Usage Examples

```gleam
// Construction from words
let user_name = name_from_words(["user", "account"])
// Ok(Name) with canonical: "user-account"

let amount_usd = name_from_words(["amount", "in", "u", "s", "d"])
// Ok(Name) with canonical: "amount-in-(usd)"

// Construction from canonical string (permissive)
let n1 = name_from_string("value-in-(usd)")    // Canonical format
let n2 = name_from_string("valueInUSD")         // camelCase (convenience)
let n3 = name_from_string("value_in_usd")       // snake_case (convenience)
// All produce equivalent Name

// Access in either form
name_to_string(amount_usd)  // "amount-in-(usd)"
name_to_words(amount_usd)   // ["amount", "in", "u", "s", "d"]

// FQName round-trip
let fqn = FQName(
  package_path(path_unchecked([name_unchecked(["morphir"]), name_unchecked(["sdk"])])),
  module_path(path_unchecked([name_unchecked(["list"])])),
  name_unchecked(["map"]),
)
fqname_to_string(fqn)  // "morphir/sdk:list#map"

let parsed = fqname_from_string("morphir/sdk:list#map")
// Ok(fqn) - lossless round-trip
```

#### JSON Schema Support

Names can be serialized as canonical strings, enabling use as object keys:

```json
{
  "types": {
    "user-account": { "...": "..." },
    "value-in-(usd)": { "...": "..." }
  }
}
```

Schema definition supporting canonical format:

```yaml
Name:
  type: string
  pattern: "^[a-z0-9]+(-[a-z0-9]+|-(\\([a-z]+\\)))*$"
  description: "Canonical name: kebab-case with abbreviations in parentheses"
  examples:
    - "user-account"
    - "value-in-(usd)"
    - "get-(html)-content"

Path:
  type: string
  pattern: "^[a-z0-9-()]+(/[a-z0-9-()]+)*$"
  description: "Canonical path: names joined by /"
  examples:
    - "main/domain"
    - "morphir/sdk"

FQName:
  type: string
  pattern: "^[a-z0-9-()/]+:[a-z0-9-()/]+#[a-z0-9-()]+$"
  description: "Canonical FQName: package:module#name"
  examples:
    - "morphir/sdk:list#map"
    - "my-org/project:main/domain#get-(html)"
```

### Access Control Module

```gleam
// === access.gleam ===

/// Visibility level for definitions
pub type Access {
  Public
  Private
}

/// Wraps any definition with visibility control
pub type AccessControlled(a) {
  AccessControlled(access: Access, value: a)
}
```

### Types Module

```gleam
// === types.gleam ===

// Note: TypeVariable is defined in naming.gleam as an opaque newtype wrapper

// ============================================================
// TYPE EXPRESSIONS (What shape is this data?)
// ============================================================

/// Type expressions
pub type Type(attributes) {
  /// Type variable: `a`, `comparable`
  Variable(attributes: attributes, name: TypeVariable)

  /// Reference to named type: `String`, `MyModule.User`
  Reference(
    attributes: attributes,
    fqname: FQName,
    args: List(Type(attributes)),
  )

  /// Tuple: `(Int, String)`
  Tuple(attributes: attributes, elements: List(Type(attributes)))

  /// Record: `{ name: String, age: Int }`
  Record(attributes: attributes, fields: List(Field(attributes)))

  /// Extensible record: `{ a | name: String }`
  ExtensibleRecord(
    attributes: attributes,
    variable: TypeVariable,
    fields: List(Field(attributes)),
  )

  /// Function: `Int -> String`
  Function(
    attributes: attributes,
    arg: Type(attributes),
    result: Type(attributes),
  )

  /// Unit type: `()`
  Unit(attributes: attributes)
}

/// Record field
pub type Field(attributes) {
  Field(name: Name, field_type: Type(attributes))
}

/// Constructor for custom types
pub type Constructor(attributes) {
  Constructor(name: Name, args: List(#(Name, Type(attributes))))
}

pub type Constructors(attributes) =
  List(Constructor(attributes))

// ============================================================
// TYPE SPECIFICATIONS (Public Interface)
// ============================================================

/// Details for derived type conversion
pub type DerivedTypeSpecificationDetails(attributes) {
  DerivedTypeSpecificationDetails(
    base_type: Type(attributes),
    from_base_type: FQName,  // Constructor: BaseType -> DerivedType
    to_base_type: FQName,    // Accessor: DerivedType -> BaseType
  )
}

/// Type specification - the public contract exposed to consumers
pub type TypeSpecification(attributes) {
  /// Type alias visible to consumers
  TypeAliasSpecification(
    params: List(TypeVariable),
    body: Type(attributes),
  )

  /// Opaque - no structure, no conversion (not serializable via Morphir)
  OpaqueTypeSpecification(params: List(TypeVariable))

  /// Custom type with public constructors
  CustomTypeSpecification(
    params: List(TypeVariable),
    constructors: Constructors(attributes),
  )

  /// Derived - opaque structure BUT with conversion functions (serializable)
  DerivedTypeSpecification(
    params: List(TypeVariable),
    details: DerivedTypeSpecificationDetails(attributes),
  )
}

// ============================================================
// TYPE DEFINITIONS (Implementation)
// ============================================================

/// Reason a type definition is incomplete
pub type Incompleteness {
  /// Reference to something that was deleted/renamed
  Hole(reason: HoleReason)
  /// Author-marked work-in-progress
  Draft(notes: Option(String))
}

/// Specific reason for a Hole
pub type HoleReason {
  UnresolvedReference(target: FQName)
  DeletedDuringRefactor(tx_id: String)
  TypeMismatch(expected: String, found: String)
}

/// Type definition - the full implementation owned by the module
pub type TypeDefinition(attributes) {
  /// Sum type implementation
  CustomTypeDefinition(
    params: List(TypeVariable),
    access: AccessControlled(Constructors(attributes)),
  )

  /// Type alias implementation
  TypeAliasDefinition(params: List(TypeVariable), body: Type(attributes))

  /// Incomplete type (v4: Hole or Draft)
  IncompleteTypeDefinition(
    params: List(TypeVariable),
    incompleteness: Incompleteness,
    partial_body: Option(Type(attributes)),
  )
}
```

### Literals Module

```gleam
// === literal.gleam ===

/// Literal constant values
pub type Literal {
  /// Boolean: true, false
  BoolLiteral(value: Bool)

  /// Single character
  CharLiteral(value: String)

  /// Text string
  StringLiteral(value: String)

  /// Integer (arbitrary precision in IR)
  WholeNumberLiteral(value: Int)

  /// Floating-point
  FloatLiteral(value: Float)

  /// Arbitrary-precision decimal (stored as string for precision)
  DecimalLiteral(value: String)
}
```

### Patterns Module

```gleam
// === pattern.gleam ===

/// Patterns for destructuring and matching
pub type Pattern(attributes) {
  /// Matches anything, binds nothing: `_`
  WildcardPattern(attributes: attributes)

  /// Binds a name while matching: `x` or `(a, b) as pair`
  AsPattern(
    attributes: attributes,
    pattern: Pattern(attributes),
    name: Name,
  )

  /// Matches tuple: `(a, b, c)`
  TuplePattern(
    attributes: attributes,
    elements: List(Pattern(attributes)),
  )

  /// Matches constructor: `Just x`, `Nothing`
  ConstructorPattern(
    attributes: attributes,
    constructor: FQName,
    args: List(Pattern(attributes)),
  )

  /// Matches empty list: `[]`
  EmptyListPattern(attributes: attributes)

  /// Matches head :: tail: `x :: xs`
  HeadTailPattern(
    attributes: attributes,
    head: Pattern(attributes),
    tail: Pattern(attributes),
  )

  /// Matches literal: `42`, `"hello"`, `True`
  LiteralPattern(attributes: attributes, literal: Literal)

  /// Matches unit: `()`
  UnitPattern(attributes: attributes)
}
```

### Values Module

```gleam
// === value.gleam ===

/// Value expressions - the core computation language
pub type Value(attributes) {
  // ===== Literals & Data Construction =====

  /// Literal constant
  Literal(attributes: attributes, literal: Literal)

  /// Constructor reference: `Just`, `Nothing`
  Constructor(attributes: attributes, fqname: FQName)

  /// Tuple: `(1, "hello", True)`
  Tuple(attributes: attributes, elements: List(Value(attributes)))

  /// List: `[1, 2, 3]`
  List(attributes: attributes, items: List(Value(attributes)))

  /// Record: `{ name = "Alice", age = 30 }`
  /// Field order does not affect equality
  Record(attributes: attributes, fields: Dict(Name, Value(attributes)))

  /// Unit value: `()`
  Unit(attributes: attributes)

  // ===== References =====

  /// Variable reference: `x`, `myValue`
  Variable(attributes: attributes, name: Name)

  /// Reference to defined value: `List.map`, `MyModule.myFunction`
  Reference(attributes: attributes, fqname: FQName)

  // ===== Field Access =====

  /// Field access: `record.fieldName`
  Field(
    attributes: attributes,
    record: Value(attributes),
    field_name: Name,
  )

  /// Field accessor function: `.fieldName`
  FieldFunction(attributes: attributes, field_name: Name)

  // ===== Function Application =====

  /// Function application: `f x` (curried, one arg at a time)
  Apply(
    attributes: attributes,
    function: Value(attributes),
    argument: Value(attributes),
  )

  /// Lambda: `\x -> x + 1`
  Lambda(
    attributes: attributes,
    argument_pattern: Pattern(attributes),
    body: Value(attributes),
  )

  // ===== Let Bindings =====

  /// Single let binding: `let x = 1 in x + 1`
  LetDefinition(
    attributes: attributes,
    name: Name,
    definition: ValueDefinitionBody(attributes),
    in_value: Value(attributes),
  )

  /// Mutually recursive let: `let f = ... g ...; g = ... f ... in ...`
  LetRecursion(
    attributes: attributes,
    bindings: Dict(Name, ValueDefinitionBody(attributes)),
    in_value: Value(attributes),
  )

  /// Pattern destructuring: `let (a, b) = tuple in a + b`
  Destructure(
    attributes: attributes,
    pattern: Pattern(attributes),
    value_to_destructure: Value(attributes),
    in_value: Value(attributes),
  )

  // ===== Control Flow =====

  /// Conditional: `if cond then a else b`
  IfThenElse(
    attributes: attributes,
    condition: Value(attributes),
    then_branch: Value(attributes),
    else_branch: Value(attributes),
  )

  /// Pattern match: `case x of ...`
  PatternMatch(
    attributes: attributes,
    subject: Value(attributes),
    cases: List(#(Pattern(attributes), Value(attributes))),
  )

  // ===== Record Update =====

  /// Record update: `{ record | field = newValue }`
  /// Field order does not affect equality
  UpdateRecord(
    attributes: attributes,
    record: Value(attributes),
    updates: Dict(Name, Value(attributes)),
  )

  // ===== Special Values (v4 additions) =====

  /// Incomplete/broken reference (for best-effort generation)
  Hole(
    attributes: attributes,
    reason: HoleReason,
    expected_type: Option(Type(attributes)),
  )

  /// Native platform operation (no IR body)
  Native(
    attributes: attributes,
    fqname: FQName,
    native_info: NativeInfo,
  )

  /// External FFI call
  External(
    attributes: attributes,
    external_name: String,
    target_platform: String,
  )
}

/// Information about native operations
pub type NativeInfo {
  NativeInfo(
    hint: NativeHint,
    description: Option(String),
  )
}

pub type NativeHint {
  /// Basic arithmetic/logic operation
  Arithmetic
  /// Comparison operation
  Comparison
  /// String operation
  StringOp
  /// Collection operation (map, filter, fold, etc.)
  CollectionOp
  /// Platform-specific operation
  PlatformSpecific(platform: String)
}
```

### Value Definitions Module

```gleam
// === value_definition.gleam ===

/// The body of a value definition (used in let bindings and top-level definitions)
pub type ValueDefinitionBody(attributes) {
  /// Normal IR expression body
  ExpressionBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Type(attributes),
    body: Value(attributes),
  )

  /// Native/builtin operation (no IR body)
  NativeBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Type(attributes),
    native_info: NativeInfo,
  )

  /// External FFI (no IR body)
  ExternalBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Type(attributes),
    external_name: String,
    target_platform: String,
  )

  /// Incomplete definition (v4 - best-effort support)
  IncompleteBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Option(Type(attributes)),
    incompleteness: Incompleteness,
    partial_body: Option(Value(attributes)),
  )
}

/// Top-level value definition (in a module)
pub type ValueDefinition(attributes) {
  ValueDefinition(
    body: AccessControlled(ValueDefinitionBody(attributes)),
  )
}

/// Value specification - the public interface (signature only, no implementation)
pub type ValueSpecification(attributes) {
  ValueSpecification(
    inputs: List(#(Name, Type(attributes))),
    output: Type(attributes),
  )
}
```

### Module Structure

Modules are containers for types and values within a package. They follow the specification/definition split pattern.

```gleam
// === module.gleam ===

// ============================================================
// DOCUMENTATION TYPE
// ============================================================

/// Opaque documentation type supporting single or multi-line content
/// Stored internally as normalized lines (no trailing \r)
pub opaque type Documentation {
  Documentation(lines: List(String))
}

/// Create documentation from a single string
/// Handles both Unix (\n) and Windows (\r\n) line endings
pub fn doc_from_string(s: String) -> Documentation {
  s
  |> string.split("\n")
  |> list.map(fn(line) { string.trim_end(line, "\r") })
  |> Documentation
}

/// Create documentation from a list of lines
/// Normalizes any trailing \r from each line
pub fn doc_from_lines(lines: List(String)) -> Documentation {
  lines
  |> list.map(fn(line) { string.trim_end(line, "\r") })
  |> Documentation
}

/// Get documentation as a single string (joins with newlines)
pub fn doc_to_string(d: Documentation) -> String {
  let Documentation(lines) = d
  string.join(lines, "\n")
}

/// Get documentation as individual lines
pub fn doc_to_lines(d: Documentation) -> List(String) {
  let Documentation(lines) = d
  lines
}

/// Check if documentation is single-line
pub fn doc_is_single_line(d: Documentation) -> Bool {
  let Documentation(lines) = d
  list.length(lines) <= 1
}

// ============================================================
// DOCUMENTED WRAPPER
// ============================================================

/// Generic documentation wrapper
pub type Documented(a) {
  Documented(
    doc: Option(Documentation),
    value: a,
  )
}

/// Create a documented value with no documentation
pub fn undocumented(value: a) -> Documented(a) {
  Documented(doc: None, value: value)
}

/// Create a documented value with a doc string
pub fn with_doc(value: a, doc: String) -> Documented(a) {
  Documented(doc: Some(doc_from_string(doc)), value: value)
}

/// Create a documented value with multi-line docs
pub fn with_doc_lines(value: a, lines: List(String)) -> Documented(a) {
  Documented(doc: Some(doc_from_lines(lines)), value: value)
}

// ============================================================
// MODULE TYPES
// ============================================================

/// Module specification - the public interface exposed to consumers
/// Contains only public types and value signatures (no implementations)
pub type ModuleSpecification(attributes) {
  ModuleSpecification(
    types: Dict(Name, Documented(TypeSpecification(attributes))),
    values: Dict(Name, Documented(ValueSpecification(attributes))),
  )
}

/// Module definition - the full implementation
/// Contains all types and values including private ones
pub type ModuleDefinition(attributes) {
  ModuleDefinition(
    types: Dict(Name, AccessControlled(Documented(TypeDefinition(attributes)))),
    values: Dict(Name, AccessControlled(Documented(ValueDefinition(attributes)))),
  )
}
```

#### Module Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage structure | `Dict(Name, ...)` | O(1) lookup by name, canonical key ordering |
| Documentation | Opaque `Documentation` type | Multi-line support, cross-platform line endings |
| Doc wrapper | Generic `Documented(a)` | Reusable across specs and defs |
| Access control | On definitions only | Specs are always public by definition |

#### Deriving Specification from Definition

A module specification can be derived from a definition by filtering to public items:

```gleam
/// Extract the public specification from a module definition
pub fn to_specification(
  def: ModuleDefinition(attributes),
) -> ModuleSpecification(attributes) {
  ModuleSpecification(
    types: def.types
      |> dict.filter(fn(_, ac) { ac.access == Public })
      |> dict.map(fn(_, ac) { to_type_spec(ac.value) }),
    values: def.values
      |> dict.filter(fn(_, ac) { ac.access == Public })
      |> dict.map(fn(_, ac) { to_value_spec(ac.value) }),
  )
}

/// Convert a TypeDefinition to its TypeSpecification
fn to_type_spec(
  documented: Documented(TypeDefinition(attributes)),
) -> Documented(TypeSpecification(attributes)) {
  Documented(
    doc: documented.doc,
    value: case documented.value {
      CustomTypeDefinition(params, constructors) ->
        CustomTypeSpecification(params, constructors.value)
      TypeAliasDefinition(params, body) ->
        TypeAliasSpecification(params, body)
      IncompleteTypeDefinition(params, _, _) ->
        // Incomplete types expose as opaque
        OpaqueTypeSpecification(params)
    },
  )
}

/// Convert a ValueDefinition to its ValueSpecification
fn to_value_spec(
  documented: Documented(ValueDefinition(attributes)),
) -> Documented(ValueSpecification(attributes)) {
  let body = documented.value.body.value
  Documented(
    doc: documented.doc,
    value: ValueSpecification(
      inputs: get_input_types(body),
      output: get_output_type(body),
    ),
  )
}
```

### Package Structure

Packages are versioned collections of modules that form a distributable unit.

```gleam
// === package.gleam ===

/// Package specification - public interface for dependency resolution
/// Used when this package is a dependency of another
pub type PackageSpecification(attributes) {
  PackageSpecification(
    modules: Dict(ModulePath, ModuleSpecification(attributes)),
  )
}

/// Package definition - complete implementation
/// Used for the local project being compiled
pub type PackageDefinition(attributes) {
  PackageDefinition(
    modules: Dict(ModulePath, AccessControlled(ModuleDefinition(attributes))),
  )
}
```

#### Package Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Module access | AccessControlled on definitions | Modules can be package-private |
| No module docs | Docs at type/value level | Module-level docs in separate metadata |
| Path as key | `Dict(ModulePath, ...)` | Hierarchical organization preserved |

### Distribution Structure

A Distribution is the top-level container representing a complete compilation unit with its dependencies.

```gleam
// === distribution.gleam ===

/// Distribution variants
pub type Distribution(attributes) {
  /// A library distribution - reusable package with implementations
  Library(library: LibraryDistribution(attributes))

  /// A specs distribution - specifications only (no implementations)
  /// Used for native/external dependencies, FFI bindings, SDK primitives
  Specs(specs: SpecsDistribution(attributes))

  // Future: Application(application: ApplicationDistribution(attributes))
}

/// Library distribution - a package plus its resolved dependencies
/// Contains full definitions (implementations)
pub type LibraryDistribution(attributes) {
  LibraryDistribution(
    /// The package being compiled/distributed
    package: PackageInfo,
    /// Full definition of the local package
    definition: PackageDefinition(attributes),
    /// Resolved dependency specifications (not full definitions)
    dependencies: Dict(PackagePath, PackageSpecification(attributes)),
  )
}

/// Specs distribution - specifications only, no implementations
/// Used for:
/// - Native/FFI bindings (types exist but implementations are platform-specific)
/// - External SDKs (Morphir.SDK basics implemented natively per-platform)
/// - Third-party packages where only the public API is needed for type-checking
pub type SpecsDistribution(attributes) {
  SpecsDistribution(
    /// The package being described
    package: PackageInfo,
    /// Public specifications only (no implementations)
    specification: PackageSpecification(attributes),
    /// Other specs this depends on (also specification-only)
    dependencies: Dict(PackagePath, PackageSpecification(attributes)),
  )
}

/// Package metadata
pub type PackageInfo {
  PackageInfo(
    name: PackagePath,
    version: SemanticVersion,
  )
}
```

#### Distribution Type Comparison

| Aspect | Library | Specs |
|--------|---------|-------|
| **Contains** | Definitions (implementations) | Specifications (interfaces only) |
| **Use case** | Normal Morphir packages | Native bindings, FFI, SDK primitives |
| **Type files** | TypeDefinition | TypeSpecification |
| **Value files** | ValueDefinition | ValueSpecification |
| **Code generation** | Full implementation | Platform-specific stub/binding |

### Semantic Versioning

Full semantic version support per the [SemVer 2.0.0 specification](https://semver.org/).

```gleam
// === semver.gleam ===

/// Semantic version with full pre-release and build metadata support
/// Format: MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
pub type SemanticVersion {
  SemanticVersion(
    major: Int,
    minor: Int,
    patch: Int,
    pre_release: Option(PreRelease),
    build_metadata: Option(BuildMetadata),
  )
}

/// Pre-release version identifiers
/// Examples: alpha, alpha.1, 0.3.7, x.7.z.92
pub type PreRelease {
  PreRelease(identifiers: List(PreReleaseIdentifier))
}

/// A pre-release identifier is either numeric or alphanumeric
pub type PreReleaseIdentifier {
  NumericIdentifier(value: Int)
  AlphanumericIdentifier(value: String)
}

/// Build metadata (ignored in version precedence)
/// Examples: 001, 20130313144700, exp.sha.5114f85
pub type BuildMetadata {
  BuildMetadata(identifiers: List(String))
}

/// Parse a semantic version string
pub fn semver_from_string(s: String) -> Result(SemanticVersion, String) {
  // Split off build metadata first (after +)
  let #(version_pre, build) = case string.split(s, "+") {
    [vp, b] -> #(vp, Some(parse_build_metadata(b)))
    [vp] -> #(vp, None)
    _ -> #(s, None)
  }

  // Split off pre-release (after -)
  let #(version, pre) = case string.split_once(version_pre, "-") {
    Ok(#(v, p)) -> #(v, Some(parse_pre_release(p)))
    Error(_) -> #(version_pre, None)
  }

  // Parse core version
  case string.split(version, ".") {
    [maj, min, pat] -> {
      use major <- result.try(int.parse(maj) |> result.map_error(fn(_) { "Invalid major" }))
      use minor <- result.try(int.parse(min) |> result.map_error(fn(_) { "Invalid minor" }))
      use patch <- result.try(int.parse(pat) |> result.map_error(fn(_) { "Invalid patch" }))
      Ok(SemanticVersion(major, minor, patch, pre, build))
    }
    _ -> Error("Invalid version format: expected MAJOR.MINOR.PATCH")
  }
}

/// Render semantic version to canonical string
pub fn semver_to_string(v: SemanticVersion) -> String {
  let core = int.to_string(v.major) <> "." <>
             int.to_string(v.minor) <> "." <>
             int.to_string(v.patch)

  let with_pre = case v.pre_release {
    Some(pre) -> core <> "-" <> pre_release_to_string(pre)
    None -> core
  }

  case v.build_metadata {
    Some(build) -> with_pre <> "+" <> build_metadata_to_string(build)
    None -> with_pre
  }
}

fn pre_release_to_string(pre: PreRelease) -> String {
  pre.identifiers
  |> list.map(fn(id) {
    case id {
      NumericIdentifier(n) -> int.to_string(n)
      AlphanumericIdentifier(s) -> s
    }
  })
  |> string.join(".")
}

fn build_metadata_to_string(build: BuildMetadata) -> String {
  string.join(build.identifiers, ".")
}

fn parse_pre_release(s: String) -> PreRelease {
  PreRelease(
    identifiers: s
      |> string.split(".")
      |> list.map(fn(part) {
        case int.parse(part) {
          Ok(n) -> NumericIdentifier(n)
          Error(_) -> AlphanumericIdentifier(part)
        }
      }),
  )
}

fn parse_build_metadata(s: String) -> BuildMetadata {
  BuildMetadata(identifiers: string.split(s, "."))
}

/// Compare two semantic versions for precedence
/// Build metadata is ignored per SemVer spec
pub fn semver_compare(a: SemanticVersion, b: SemanticVersion) -> Order {
  // Compare core version first
  case int.compare(a.major, b.major) {
    Eq -> case int.compare(a.minor, b.minor) {
      Eq -> case int.compare(a.patch, b.patch) {
        Eq -> compare_pre_release(a.pre_release, b.pre_release)
        other -> other
      }
      other -> other
    }
    other -> other
  }
}

/// Pre-release versions have lower precedence than normal
fn compare_pre_release(a: Option(PreRelease), b: Option(PreRelease)) -> Order {
  case a, b {
    None, None -> Eq
    Some(_), None -> Lt  // Pre-release < release
    None, Some(_) -> Gt  // Release > pre-release
    Some(pa), Some(pb) -> compare_pre_release_identifiers(pa.identifiers, pb.identifiers)
  }
}

fn compare_pre_release_identifiers(
  a: List(PreReleaseIdentifier),
  b: List(PreReleaseIdentifier),
) -> Order {
  case a, b {
    [], [] -> Eq
    [], _ -> Lt   // Fewer fields = lower precedence
    _, [] -> Gt
    [ha, ..ta], [hb, ..tb] -> {
      case compare_identifier(ha, hb) {
        Eq -> compare_pre_release_identifiers(ta, tb)
        other -> other
      }
    }
  }
}

fn compare_identifier(a: PreReleaseIdentifier, b: PreReleaseIdentifier) -> Order {
  case a, b {
    NumericIdentifier(na), NumericIdentifier(nb) -> int.compare(na, nb)
    AlphanumericIdentifier(sa), AlphanumericIdentifier(sb) -> string.compare(sa, sb)
    NumericIdentifier(_), AlphanumericIdentifier(_) -> Lt  // Numeric < alpha
    AlphanumericIdentifier(_), NumericIdentifier(_) -> Gt
  }
}
```

#### Semantic Version Examples

| Version String | Parsed |
|----------------|--------|
| `1.0.0` | `SemanticVersion(1, 0, 0, None, None)` |
| `1.0.0-alpha` | `SemanticVersion(1, 0, 0, Some(PreRelease([Alpha("alpha")])), None)` |
| `1.0.0-alpha.1` | `SemanticVersion(1, 0, 0, Some(PreRelease([Alpha("alpha"), Num(1)])), None)` |
| `1.0.0-0.3.7` | `SemanticVersion(1, 0, 0, Some(PreRelease([Num(0), Num(3), Num(7)])), None)` |
| `1.0.0+20130313` | `SemanticVersion(1, 0, 0, None, Some(BuildMetadata(["20130313"])))` |
| `1.0.0-beta+exp.sha.5114f85` | Full version with pre-release and build metadata |

#### Version Precedence (lowest to highest)

```
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta
< 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
```

### Distribution Modes

```gleam
/// Distribution layout mode
pub type DistributionMode {
  /// Single JSON blob containing entire IR
  ClassicMode
  /// Directory tree with individual files per definition
  VfsMode
}

/// VFS distribution manifest (format.json)
pub type VfsManifest {
  VfsManifest(
    format_version: String,
    layout: DistributionMode,
    package: PackagePath,
    created: String,  // ISO 8601 timestamp
  )
}

/// VFS module manifest (module.json)
pub type VfsModuleManifest {
  VfsModuleManifest(
    format_version: String,
    path: ModulePath,
    types: List(Name),
    values: List(Name),
  )
}
```

#### Distribution Modes Comparison

| Mode | Structure | Use Case |
|------|-----------|----------|
| **Classic** | Single `morphir-ir.json` blob | Simple projects, backwards compatibility |
| **VFS** | `.morphir-dist/` directory tree | Large projects, incremental updates, shell tools |

#### IR Hierarchy Summary

```
Distribution
├── Library(LibraryDistribution)
│   ├── package: PackageInfo (name, version)
│   ├── definition: PackageDefinition
│   │   └── modules: Dict(ModulePath, AccessControlled(ModuleDefinition))
│   │       └── ModuleDefinition
│   │           ├── types: Dict(Name, AccessControlled(Documented(TypeDefinition)))
│   │           └── values: Dict(Name, AccessControlled(Documented(ValueDefinition)))
│   └── dependencies: Dict(PackagePath, PackageSpecification)
│
└── Specs(SpecsDistribution)
    ├── package: PackageInfo (name, version)
    ├── specification: PackageSpecification
    │   └── modules: Dict(ModulePath, ModuleSpecification)
    │       └── ModuleSpecification
    │           ├── types: Dict(Name, Documented(TypeSpecification))
    │           └── values: Dict(Name, Documented(ValueSpecification))
    └── dependencies: Dict(PackagePath, PackageSpecification)
```

## JSON Serialization

### Design Decisions

| Concern | Rule |
|---------|------|
| **Encoding (output)** | Wrapper object style, omit null and empty fields |
| **Decoding (input)** | Permissive - accept wrapper object OR tagged array (v1/v2/v3 compat) |
| **Field naming** | camelCase for JSON fields |
| **FQName/Name** | Canonical string format |

### Wrapper Object Encoding

Sum types are encoded as single-key objects where the key is the variant name:

```json
{ "VariantName": { ...fields } }
```

### Null and Empty Omission

To minimize payload size:
- Omit fields with `null` value
- Omit empty arrays `[]`
- Omit `attributes` when null/empty

### Type Expression Examples

#### Variable

```json
{ "Variable": { "name": "a" } }
```

#### Reference (no type arguments)

```json
{ "Reference": { "fqname": "morphir/sdk:basics#int" } }
```

#### Reference (with type arguments)

```json
{
  "Reference": {
    "fqname": "morphir/sdk:list#list",
    "args": [
      { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    ]
  }
}
```

#### Tuple

```json
{
  "Tuple": {
    "elements": [
      { "Reference": { "fqname": "morphir/sdk:basics#int" } },
      { "Reference": { "fqname": "morphir/sdk:string#string" } }
    ]
  }
}
```

#### Record

Field names as object keys, values are the field types directly:

```json
{
  "Record": {
    "fields": {
      "user-name": { "Reference": { "fqname": "morphir/sdk:string#string" } },
      "age": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    }
  }
}
```

#### ExtensibleRecord

```json
{
  "ExtensibleRecord": {
    "variable": "a",
    "fields": {
      "name": { "Reference": { "fqname": "morphir/sdk:string#string" } }
    }
  }
}
```

:::note
Decoding also accepts the legacy array format for backwards compatibility:
```json
{ "Record": { "fields": [{ "name": "age", "fieldType": { "Reference": { "fqname": "..." } } }] } }
```
:::

#### Function

```json
{
  "Function": {
    "arg": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
    "result": { "Reference": { "fqname": "morphir/sdk:string#string" } }
  }
}
```

#### Unit

```json
{ "Unit": {} }
```

### Type Definition Examples

#### CustomTypeDefinition

`type Maybe a = Just a | Nothing`

```json
{
  "CustomTypeDefinition": {
    "params": ["a"],
    "access": {
      "access": "Public",
      "value": [
        { "name": "just", "args": [["value", { "Variable": { "name": "a" } }]] },
        { "name": "nothing" }
      ]
    }
  }
}
```

#### TypeAliasDefinition

`type alias UserId = String`

```json
{
  "TypeAliasDefinition": {
    "body": { "Reference": { "fqname": "morphir/sdk:string#string" } }
  }
}
```

#### IncompleteTypeDefinition (v4)

```json
{
  "IncompleteTypeDefinition": {
    "params": ["a"],
    "incompleteness": {
      "Hole": {
        "reason": { "UnresolvedReference": { "target": "my-org/project:domain#missing-type" } }
      }
    }
  }
}
```

### Type Specification Examples

#### DerivedTypeSpecification

`LocalDate` backed by `String` with conversion functions:

```json
{
  "DerivedTypeSpecification": {
    "details": {
      "baseType": { "Reference": { "fqname": "morphir/sdk:string#string" } },
      "fromBaseType": "my-org/sdk:local-date#from-string",
      "toBaseType": "my-org/sdk:local-date#to-string"
    }
  }
}
```

### Backwards Compatible Decoding

The decoder accepts multiple formats for compatibility with v1/v2/v3:

| Format | Example | Source |
|--------|---------|--------|
| Wrapper object | `{ "Variable": { "name": "a" } }` | v4 canonical |
| Tagged array (capitalized) | `["Variable", {}, ["a"]]` | v2/v3 |
| Tagged array (lowercase) | `["variable", {}, ["a"]]` | v1 |

```gleam
/// Decode a Type from JSON, accepting multiple formats
pub fn decode_type(json: Dynamic) -> Result(Type, DecodeError) {
  // Try wrapper object first (v4 canonical)
  case decode_wrapper_object(json) {
    Ok(t) -> Ok(t)
    Error(_) -> {
      // Fall back to tagged array (v1/v2/v3 compat)
      decode_tagged_array(json)
    }
  }
}
```

### Literal Examples

```json
{ "BoolLiteral": { "value": true } }
{ "StringLiteral": { "value": "hello world" } }
{ "WholeNumberLiteral": { "value": 42 } }
{ "FloatLiteral": { "value": 3.14159 } }
{ "DecimalLiteral": { "value": "123456789.987654321" } }
{ "CharLiteral": { "value": "A" } }
```

### Pattern Examples

#### WildcardPattern

```json
{ "WildcardPattern": {} }
```

#### AsPattern (variable binding)

Name becomes the key, pattern is the value:

```json
{ "AsPattern": { "x": { "WildcardPattern": {} } } }
```

Simple variable binding (most common case):

```json
{ "AsPattern": { "user-name": { "WildcardPattern": {} } } }
```

#### TuplePattern

```json
{
  "TuplePattern": {
    "elements": [
      { "AsPattern": { "a": { "WildcardPattern": {} } } },
      { "AsPattern": { "b": { "WildcardPattern": {} } } }
    ]
  }
}
```

#### ConstructorPattern

```json
{
  "ConstructorPattern": {
    "constructor": "morphir/sdk:maybe#just",
    "args": [
      { "AsPattern": { "value": { "WildcardPattern": {} } } }
    ]
  }
}
```

#### HeadTailPattern

```json
{
  "HeadTailPattern": {
    "head": { "AsPattern": { "x": { "WildcardPattern": {} } } },
    "tail": { "AsPattern": { "xs": { "WildcardPattern": {} } } }
  }
}
```

#### LiteralPattern

```json
{ "LiteralPattern": { "literal": { "WholeNumberLiteral": { "value": 42 } } } }
```

### Value Expression Examples

#### Literal

```json
{
  "Literal": {
    "literal": { "WholeNumberLiteral": { "value": 42 } }
  }
}
```

#### Variable

```json
{ "Variable": { "name": "user-name" } }
```

#### Reference

```json
{ "Reference": { "fqname": "morphir/sdk:list#map" } }
```

#### Constructor

```json
{ "Constructor": { "fqname": "morphir/sdk:maybe#just" } }
```

#### Tuple

```json
{
  "Tuple": {
    "elements": [
      { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } },
      { "Literal": { "literal": { "StringLiteral": { "value": "hello" } } } }
    ]
  }
}
```

#### List

```json
{
  "List": {
    "items": [
      { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } },
      { "Literal": { "literal": { "WholeNumberLiteral": { "value": 2 } } } }
    ]
  }
}
```

#### Record (fields as object keys, sorted alphabetically)

```json
{
  "Record": {
    "fields": {
      "age": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 30 } } } },
      "name": { "Literal": { "literal": { "StringLiteral": { "value": "Alice" } } } }
    }
  }
}
```

#### Field Access

```json
{
  "Field": {
    "record": { "Variable": { "name": "user" } },
    "fieldName": "email"
  }
}
```

#### FieldFunction

```json
{ "FieldFunction": { "fieldName": "email" } }
```

#### Apply (function application)

```json
{
  "Apply": {
    "function": { "Reference": { "fqname": "morphir/sdk:list#map" } },
    "argument": { "Variable": { "name": "transform" } }
  }
}
```

#### Lambda

```json
{
  "Lambda": {
    "argumentPattern": { "AsPattern": { "x": { "WildcardPattern": {} } } },
    "body": {
      "Apply": {
        "function": {
          "Apply": {
            "function": { "Reference": { "fqname": "morphir/sdk:basics#add" } },
            "argument": { "Variable": { "name": "x" } }
          }
        },
        "argument": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } }
      }
    }
  }
}
```

#### LetDefinition

Name becomes the key:

```json
{
  "LetDefinition": {
    "x": {
      "def": {
        "ExpressionBody": {
          "outputType": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
          "body": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 42 } } } }
        }
      },
      "inValue": {
        "Apply": {
          "function": {
            "Apply": {
              "function": { "Reference": { "fqname": "morphir/sdk:basics#add" } },
              "argument": { "Variable": { "name": "x" } }
            }
          },
          "argument": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } }
        }
      }
    }
  }
}
```

#### LetRecursion

Binding names as keys:

```json
{
  "LetRecursion": {
    "bindings": {
      "is-even": {
        "ExpressionBody": {
          "inputTypes": [["n", { "Reference": { "fqname": "morphir/sdk:basics#int" } }]],
          "outputType": { "Reference": { "fqname": "morphir/sdk:basics#bool" } },
          "body": { "Variable": { "name": "..." } }
        }
      },
      "is-odd": {
        "ExpressionBody": {
          "inputTypes": [["n", { "Reference": { "fqname": "morphir/sdk:basics#int" } }]],
          "outputType": { "Reference": { "fqname": "morphir/sdk:basics#bool" } },
          "body": { "Variable": { "name": "..." } }
        }
      }
    },
    "inValue": { "Variable": { "name": "is-even" } }
  }
}
```

#### IfThenElse

```json
{
  "IfThenElse": {
    "condition": { "Variable": { "name": "is-valid" } },
    "thenBranch": { "Literal": { "literal": { "StringLiteral": { "value": "yes" } } } },
    "elseBranch": { "Literal": { "literal": { "StringLiteral": { "value": "no" } } } }
  }
}
```

#### PatternMatch

```json
{
  "PatternMatch": {
    "subject": { "Variable": { "name": "maybe-value" } },
    "cases": [
      [
        { "ConstructorPattern": { "constructor": "morphir/sdk:maybe#just", "args": [{ "AsPattern": { "v": { "WildcardPattern": {} } } }] } },
        { "Variable": { "name": "v" } }
      ],
      [
        { "ConstructorPattern": { "constructor": "morphir/sdk:maybe#nothing" } },
        { "Literal": { "literal": { "WholeNumberLiteral": { "value": 0 } } } }
      ]
    ]
  }
}
```

#### UpdateRecord

```json
{
  "UpdateRecord": {
    "record": { "Variable": { "name": "user" } },
    "updates": {
      "age": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 31 } } } }
    }
  }
}
```

#### Hole (v4 - incomplete value)

```json
{
  "Hole": {
    "reason": {
      "UnresolvedReference": { "target": "my-org/project:module#deleted-function" }
    },
    "expectedType": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
  }
}
```

#### Native (v4 - platform operation)

```json
{
  "Native": {
    "fqname": "morphir/sdk:basics#add",
    "nativeInfo": {
      "hint": { "Arithmetic": {} },
      "description": "Integer addition"
    }
  }
}
```

### Value Definition Examples

#### ExpressionBody

Input names as keys:

```json
{
  "ExpressionBody": {
    "inputTypes": {
      "x": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    },
    "outputType": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
    "body": {
      "Apply": {
        "function": {
          "Apply": {
            "function": { "Reference": { "fqname": "morphir/sdk:basics#add" } },
            "argument": { "Variable": { "name": "x" } }
          }
        },
        "argument": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } }
      }
    }
  }
}
```

#### NativeBody (builtin operation)

```json
{
  "NativeBody": {
    "inputTypes": {
      "a": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
      "b": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    },
    "outputType": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
    "nativeInfo": {
      "hint": { "Arithmetic": {} }
    }
  }
}
```

#### ValueSpecification (signature only)

```json
{
  "ValueSpecification": {
    "inputs": {
      "x": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
      "y": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    },
    "output": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
  }
}
```

### Module Serialization Examples

#### JSON Flattening Rules

The `Documented` and `AccessControlled` wrappers are flattened in JSON for conciseness:

| Gleam Type | JSON Representation |
|------------|---------------------|
| `Documentation` | String or array of strings (see below) |
| `Documented(a)` | `{ "doc": "...", ...a }` (doc inlined, omit if None) |
| `AccessControlled(a)` | `{ "access": "Public", ...a }` (access inlined) |
| `AccessControlled(Documented(a))` | `{ "access": "Public", "doc": "...", ...a }` |

#### Documentation Serialization

The `doc` field accepts two JSON formats:

| Format | Example | Internal Representation |
|--------|---------|-------------------------|
| String | `"Line 1\nLine 2"` | `["Line 1", "Line 2"]` (split on newlines) |
| Array | `["Line 1", "Line 2"]` | `["Line 1", "Line 2"]` (normalized) |

Both formats produce the same internal `Documentation` value.

**Line ending normalization:**
- Strings are split on `\n` (Unix line ending)
- Any trailing `\r` is trimmed from each line (handles Windows `\r\n`)
- This ensures consistent comparison regardless of source OS

```json
// String format - embedded newlines are split into lines
{ "doc": "First line.\nSecond line.\nThird line." }

// Array format - explicit line-by-line (preferred for multi-line)
{ "doc": ["First line.", "Second line.", "Third line."] }

// Simple doc (no newlines)
{ "doc": "A brief description" }
```

**Encoding rules:**
- No newlines in content → output as string
- Contains newlines → output as array (preserves readability)
- Empty/None → omit the `doc` field entirely
- Always output with `\n` line endings (Unix-style)

**Decoding rules (permissive):**
- String → split on `\n`, trim trailing `\r` from each line
- Array → normalize each line (trim trailing `\r`)
- Missing field → `None`

#### ModuleSpecification

Public interface of a module (used in dependencies):

```json
{
  "types": {
    "user": {
      "doc": [
        "Represents a user in the system.",
        "Contains identity and contact information."
      ],
      "TypeAliasSpecification": {
        "body": {
          "Record": {
            "fields": {
              "email": { "Reference": { "fqname": "morphir/sdk:string#string" } },
              "user-(id)": { "Reference": { "fqname": "my-org/domain:types#user-(id)" } }
            }
          }
        }
      }
    },
    "user-(id)": {
      "OpaqueTypeSpecification": {}
    }
  },
  "values": {
    "validate-email": {
      "doc": "Check if an email address is valid",
      "inputs": {
        "email": { "Reference": { "fqname": "morphir/sdk:string#string" } }
      },
      "output": { "Reference": { "fqname": "morphir/sdk:basics#bool" } }
    }
  }
}
```

#### ModuleDefinition

Full implementation of a module:

```json
{
  "types": {
    "user": {
      "access": "Public",
      "doc": "A user in the system",
      "TypeAliasDefinition": {
        "body": {
          "Record": {
            "fields": {
              "email": { "Reference": { "fqname": "morphir/sdk:string#string" } },
              "user-(id)": { "Reference": { "fqname": "my-org/domain:types#user-(id)" } }
            }
          }
        }
      }
    },
    "internal-cache": {
      "access": "Private",
      "doc": "Internal cache structure",
      "TypeAliasDefinition": {
        "body": {
          "Reference": {
            "fqname": "morphir/sdk:dict#dict",
            "args": [
              { "Reference": { "fqname": "morphir/sdk:string#string" } },
              { "Reference": { "fqname": "my-org/domain:types#user" } }
            ]
          }
        }
      }
    }
  },
  "values": {
    "validate-email": {
      "access": "Public",
      "doc": "Check if an email address is valid",
      "ExpressionBody": {
        "inputTypes": {
          "email": { "Reference": { "fqname": "morphir/sdk:string#string" } }
        },
        "outputType": { "Reference": { "fqname": "morphir/sdk:basics#bool" } },
        "body": { "Variable": { "name": "..." } }
      }
    }
  }
}
```

### Distribution Serialization Examples

#### Library Distribution (Classic Mode)

Single-blob `morphir-ir.json`:

```json
{
  "formatVersion": "4.0.0",
  "Library": {
    "package": {
      "name": "my-org/my-project",
      "version": "1.2.0"
    },
    "def": {
      "modules": {
        "domain/users": {
          "access": "Public",
          "types": { "...": "..." },
          "values": { "...": "..." }
        }
      }
    },
    "dependencies": {
      "morphir/sdk": {
        "modules": {
          "basics": { "types": { "...": "..." }, "values": { "...": "..." } },
          "string": { "types": { "...": "..." }, "values": { "...": "..." } },
          "list": { "types": { "...": "..." }, "values": { "...": "..." } }
        }
      }
    }
  }
}
```

#### Semantic Version Serialization

Versions are serialized as canonical strings:

```json
"1.0.0"
"2.1.0-alpha.1"
"3.0.0-rc.2+build.456"
"1.0.0+20130313144700"
```

### VFS File Format Version

All VFS node files include a `formatVersion` field using semantic versioning:

```gleam
pub type VfsNodeHeader {
  VfsNodeHeader(
    format_version: String,  // Semver: "4.0.0"
    name: Name,
  )
}
```

### Complete VFS File Examples

#### Type File

File: `.morphir-dist/pkg/my-org/domain/types/user.type.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "user",
  "def": {
    "TypeAliasDefinition": {
      "body": {
        "Record": {
          "fields": {
            "created-at": { "Reference": { "fqname": "my-org/sdk:local-date-time#local-date-time" } },
            "email": { "Reference": { "fqname": "morphir/sdk:string#string" } },
            "user-(id)": { "Reference": { "fqname": "my-org/domain:types#user-(id)" } }
          }
        }
      }
    }
  }
}
```

#### Value File

File: `.morphir-dist/pkg/my-org/domain/values/get-user-by-email.value.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "get-user-by-email",
  "def": {
    "access": "Public",
    "value": {
      "ExpressionBody": {
        "inputTypes": {
          "email": { "Reference": { "fqname": "morphir/sdk:string#string" } },
          "users": {
            "Reference": {
              "fqname": "morphir/sdk:list#list",
              "args": [{ "Reference": { "fqname": "my-org/domain:types#user" } }]
            }
          }
        },
        "outputType": {
          "Reference": {
            "fqname": "morphir/sdk:maybe#maybe",
            "args": [{ "Reference": { "fqname": "my-org/domain:types#user" } }]
          }
        },
        "body": {
          "Apply": {
            "function": {
              "Apply": {
                "function": { "Reference": { "fqname": "morphir/sdk:list#find" } },
                "argument": {
                  "Lambda": {
                    "argumentPattern": { "AsPattern": { "user": { "WildcardPattern": {} } } },
                    "body": {
                      "Apply": {
                        "function": {
                          "Apply": {
                            "function": { "Reference": { "fqname": "morphir/sdk:basics#equal" } },
                            "argument": {
                              "Field": {
                                "record": { "Variable": { "name": "user" } },
                                "fieldName": "email"
                              }
                            }
                          }
                        },
                        "argument": { "Variable": { "name": "email" } }
                      }
                    }
                  }
                }
              }
            },
            "argument": { "Variable": { "name": "users" } }
          }
        }
      }
    }
  }
}
```

#### Module File

File: `.morphir-dist/pkg/my-org/domain/module.json`

```json
{
  "formatVersion": "4.0.0",
  "path": "my-org/domain",
  "types": ["user", "user-(id)", "order"],
  "values": ["get-user-by-email", "create-order", "validate-user"]
}
```

#### Format File (Library Distribution)

File: `.morphir-dist/format.json`

```json
{
  "formatVersion": "4.0.0",
  "distribution": "Library",
  "package": "my-org/my-project",
  "version": "1.2.0",
  "created": "2026-01-15T12:00:00Z"
}
```

#### Format File (Specs Distribution)

File: `.morphir-dist/format.json`

```json
{
  "formatVersion": "4.0.0",
  "distribution": "Specs",
  "package": "morphir/sdk",
  "version": "3.0.0",
  "created": "2026-01-15T12:00:00Z"
}
```

### VFS Specification File Examples

For Specs distributions (or dependencies), files contain specifications instead of definitions.

#### Type Specification File

File: `.morphir-dist/pkg/morphir/sdk/types/int.type.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "int",
  "spec": {
    "doc": "Arbitrary precision integer",
    "OpaqueTypeSpecification": {}
  }
}
```

#### Value Specification File

File: `.morphir-dist/pkg/morphir/sdk/values/add.value.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "add",
  "spec": {
    "doc": [
      "Add two integers.",
      "This is a native operation implemented per-platform."
    ],
    "inputs": {
      "a": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
      "b": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    },
    "output": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
  }
}
```

## JSON-RPC 2.0 Protocol

### VFS Methods

#### vfs/read

Retrieve a specific node from the VFS with resolved configuration context.

```json
{
  "method": "vfs/read",
  "params": {
    "uri": "morphir://pkg/main/domain/user.type.json"
  }
}
```

#### vfs/proposeUpdate

Starts a speculative change to the IR. The Daemon verifies type-checking before committing.

```json
{
  "method": "vfs/proposeUpdate",
  "params": {
    "txId": "refactor-001",
    "ops": [
      {
        "op": "RenameType",
        "path": "main/domain",
        "oldName": "order",
        "newName": "purchase"
      }
    ],
    "dryRun": false
  }
}
```

#### vfs/commit

Finalizes a transaction.

1. The Daemon writes the `commit` line to `session.jsonl`
2. The Pending State is synced to the physical `.morphir-dist` directory
3. A `vfs/onChanged` notification is broadcast to all active backends

#### vfs/subscribe

Backends observe specific namespaces to reduce network traffic.

```json
{
  "method": "vfs/subscribe",
  "params": {
    "namespaces": ["main/domain"],
    "depth": "recursive"
  }
}
```

### Notifications

#### vfs/onChanged

Sent by the Daemon whenever the IR or Config is updated.

```json
{
  "method": "vfs/onChanged",
  "params": {
    "uri": "morphir://pkg/main/domain/order.type.json",
    "changeType": "Update",
    "content": { "..." : "..." },
    "resolvedConfig": { "..." : "..." }
  }
}
```

### IR Operations

```gleam
/// Operations for IR mutations
pub type IrOperation {
  UpsertType(path: Path, name: Name, definition: TypeDefinition(Attributes))
  UpsertValue(path: Path, name: Name, definition: ValueDefinition(Attributes))
  DeleteNode(path: Path, name: Name)
  RenameNode(path: Path, old_name: Name, new_name: Name)
}
```

## Best-Effort Generation

### Generation Status

```gleam
/// Artifact produced by code generation
pub type Artifact {
  Artifact(path: String, content: String)
}

/// Result of backend code generation
pub type GenerationStatus {
  /// Generation succeeded perfectly
  Clean(artifacts: List(Artifact))
  /// Generation succeeded with placeholders for broken call-sites
  Degraded(artifacts: List(Artifact), holes: List(HoleReport))
  /// Structural errors prevented any output
  Failed(errors: List(Diagnostic))
}
```

### Hole Report

```gleam
/// Identifies where "Best-Effort" placeholders were inserted
pub type HoleReport {
  HoleReport(
    location: SourceLocation,
    ir_reference: FQName,
    reason: HoleReason,
  )
}

pub type SourceLocation {
  SourceLocation(uri: String, range: Range)
}

pub type Range {
  Range(start: Position, end: Position)
}

pub type Position {
  Position(line: Int, character: Int)
}
```

### Diagnostic

```gleam
pub type Severity {
  Error
  Warning
  Info
}

pub type Diagnostic {
  Diagnostic(
    severity: Severity,
    code: String,
    message: String,
    range: Range,
  )
}
```

## Configuration Merge Rules

The Core Daemon provides a **Resolved Configuration View**. Layers merge in priority order (highest first):

1. **Session Overlays**: Volatile overrides sent via `vfs/setOverlay`
2. **Environment Variables**: `MORPHIR__SECTION__KEY` format
3. **Module Config**: `module.json` or local `morphir.toml`
4. **Project Config**: Root `morphir.toml`
5. **User/Global Config**: System-level defaults

## Session Management

The `session.jsonl` file is an append-only log for crash recovery and refactoring history.

```json
{"ts": "2026-01-15T11:00:00Z", "tx": "tx-1", "op": "begin"}
{"ts": "2026-01-15T11:00:01Z", "tx": "tx-1", "op": "upsert_type", "path": "my-org/domain", "name": "user", "data": {"..."}}
{"ts": "2026-01-15T11:00:05Z", "tx": "tx-1", "op": "commit"}
```

### Session Operations

```gleam
pub type SessionOp {
  Begin
  UpsertType
  UpsertValue
  DeleteNode
  SetConfigOverlay
  Commit
  Rollback
}

pub type SessionEntry {
  SessionEntry(
    ts: String,        // ISO 8601 timestamp
    tx: String,        // Transaction ID
    op: SessionOp,
    path: Option(Path),
    name: Option(Name),
    data: Option(Dynamic),
  )
}
```

## Backend Registration

Backends register with the Daemon to define their capabilities.

```gleam
pub type Transport {
  Http
  Stdio
}

pub type BackendCapabilities {
  BackendCapabilities(
    incremental: Bool,      // Supports incremental updates
    best_effort: Bool,      // Supports degraded generation
    transports: List(Transport),
  )
}

pub type BackendRegistration {
  BackendRegistration(
    name: String,
    capabilities: BackendCapabilities,
  )
}
```

## Open Questions

:::note
The following items require further design discussion:

1. ~~**Value expressions** - Complete the Value type definitions~~ ✓ Done
2. ~~**Module structure** - Define ModuleSpecification and ModuleDefinition~~ ✓ Done
3. ~~**Package/Distribution** - Define top-level containers for both modes~~ ✓ Done
4. ~~**Specs Distribution** - Define specification-only distribution type~~ ✓ Done
5. **Application Distribution** - Define `ApplicationDistribution` variant for executable distributions
6. **WASM Component Model** - Define wit interfaces for backend extensions
:::

## Appendix A: Integrity Status Summary

| Status | Meaning |
|--------|---------|
| `Clean` | Generation succeeded perfectly |
| `Degraded` | Generation succeeded with placeholders/runtime-errors for broken call-sites |
| `Failed` | Structural errors prevented any output |

## Appendix B: Placeholder Strategies

### Runtime Error (TypeScript/Scala)

```typescript
const user = morphir.runtime.hole("Unresolved Type: UserAccount", { line: 12 });
```

### Type Erasure (Java/Go)

```java
public Object processOrder(Object order) {
    /* Hole: Order type missing */
    return null;
}
```
