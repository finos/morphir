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
├── format.json            # Layout metadata and spec version
├── morphir.toml           # Project-level configuration
├── session.jsonl          # Append-only transaction journal
├── pkg/                   # Local project IR (Namespace-to-Directory)
│   └── MyOrg/
│       └── MyProject/
│           ├── module.json
│           ├── types/
│           │   └── User.type.json
│           └── values/
│               └── login.value.json
└── deps/                  # Dependency IR (versioned)
    └── Morphir.SDK/
        └── 1.2.0/
            └── ...
```

### Namespace Mapping Rules

Morphir paths (e.g., `["Main", "Domain"]`) map to physical directories:

1. `pkg/` or `deps/{pkg}/{ver}/` is the root
2. Each path segment is a PascalCase directory
3. Terminal types are suffixed `.type.json`
4. Terminal values are suffixed `.value.json`
5. Every module directory contains a `module.json`

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

### Complete VFS File Example

File: `.morphir-dist/pkg/MyOrg/Domain/types/User.type.json`

```json
{
  "name": "user",
  "definition": {
    "TypeAliasDefinition": {
      "body": {
        "Record": {
          "fields": {
            "user-(id)": { "Reference": { "fqname": "my-org/domain:types#user-(id)" } },
            "email": { "Reference": { "fqname": "morphir/sdk:string#string" } },
            "created-at": { "Reference": { "fqname": "my-org/sdk:local-date-time#local-date-time" } }
          }
        }
      }
    }
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
    "uri": "morphir://pkg/Main/Domain/User.type.json"
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
        "path": ["Main", "Domain"],
        "oldName": "Order",
        "newName": "Purchase"
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
    "namespaces": [["Main", "Domain"]],
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
    "uri": "morphir://pkg/Main/Domain/Order.type.json",
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
{"ts": "2026-01-15T11:00:01Z", "tx": "tx-1", "op": "upsert_type", "path": ["A"], "name": "B", "data": {"..."}}
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

1. **Value expressions** - Complete the Value type definitions
2. **Module structure** - Define ModuleSpecification and ModuleDefinition
3. **Package/Distribution** - Define top-level containers for both modes
4. **WASM Component Model** - Define wit interfaces for backend extensions
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
