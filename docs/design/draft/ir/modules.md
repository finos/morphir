---
title: Module Structure
sidebar_label: Modules
sidebar_position: 5
---

# Module Structure

Modules are containers for types and values within a package. They follow the specification/definition split pattern.

## Documentation Type

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
```

## Documented Wrapper

```gleam
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
```

## Module Types

```gleam
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

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage structure | `Dict(Name, ...)` | O(1) lookup by name, canonical key ordering |
| Documentation | Opaque `Documentation` type | Multi-line support, cross-platform line endings |
| Doc wrapper | Generic `Documented(a)` | Reusable across specs and defs |
| Access control | On definitions only | Specs are always public by definition |

## Deriving Specification from Definition

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

## JSON Serialization

### JSON Flattening Rules

The `Documented` and `AccessControlled` wrappers are flattened in JSON for conciseness:

| Gleam Type | JSON Representation |
|------------|---------------------|
| `Documentation` | String or array of strings (see below) |
| `Documented(a)` | `{ "doc": "...", ...a }` (doc inlined, omit if None) |
| `AccessControlled(a)` | `{ "access": "Public", ...a }` (access inlined) |
| `AccessControlled(Documented(a))` | `{ "access": "Public", "doc": "...", ...a }` |

### Documentation Serialization

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

## Module Serialization Examples

### ModuleSpecification

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

### ModuleDefinition

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
