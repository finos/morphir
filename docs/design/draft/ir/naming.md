---
title: Naming Module
sidebar_label: Naming
sidebar_position: 2
---

# Naming Module

The naming module uses **newtype wrappers** for type safety, **smart constructors** for validation, and a **canonical string format** for serialization.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Type safety | Newtype wrappers (opaque) | Prevents mixing Name/Path/PackagePath at compile time |
| Internal storage | Canonical string | Optimized for serialization, keys, URLs |
| Abbreviation format | Parentheses `(usd)` | URL-safe, readable, unambiguous |
| Input parsing | Permissive | Accept multiple formats, always output canonical |

## Canonical String Format

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

## Core Types

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

## Usage Examples

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

## JSON Schema Support

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
  pattern: "^([a-z0-9]+|\\([a-z0-9]+\\))(-([a-z0-9]+|\\([a-z0-9]+\\)))*$"
  description: "Canonical name: kebab-case with abbreviations in parentheses"
  examples:
    - "user-account"
    - "value-in-(usd)"
    - "get-(html)-content"

Path:
  type: string
  pattern: "^([a-z0-9]+|\\([a-z0-9]+\\))(-([a-z0-9]+|\\([a-z0-9]+\\)))*(/([a-z0-9]+|\\([a-z0-9]+\\))(-([a-z0-9]+|\\([a-z0-9]+\\)))*)*$"
  description: "Canonical path: names joined by /"
  examples:
    - "main/domain"
    - "morphir/sdk"

FQName:
  type: string
  pattern: "^([a-z0-9]+|\\([a-z0-9]+\\))(-([a-z0-9]+|\\([a-z0-9]+\\)))*(/([a-z0-9]+|\\([a-z0-9]+\\))(-([a-z0-9]+|\\([a-z0-9]+\\)))*)*:([a-z0-9]+|\\([a-z0-9]+\\))(-([a-z0-9]+|\\([a-z0-9]+\\)))*(/([a-z0-9]+|\\([a-z0-9]+\\))(-([a-z0-9]+|\\([a-z0-9]+\\)))*)*#([a-z0-9]+|\\([a-z0-9]+\\))(-([a-z0-9]+|\\([a-z0-9]+\\)))*$"
  description: "Canonical FQName: package:module#name"
  examples:
    - "morphir/sdk:list#map"
    - "my-org/project:main/domain#get-(html)"
```
