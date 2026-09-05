---
title: "What's New in Version 4"
linkTitle: "What's New"
weight: 1
description: "Changes and improvements in Morphir IR schema version 4"
---

# What's New in Version 4

Version 4 of the Morphir IR schema introduces explicit attribute types, canonical string formats, embedded documentation, structured annotations, and new constructs for handling incomplete code and native operations.

## Key Changes from Version 3

### 1. Explicit Attribute Types

The most significant change in version 4 is the replacement of generic attributes with explicit, structured attribute types.

#### TypeAttributes

All type expressions now use structured `TypeAttributes` instead of generic `a`:

**V3 format (generic attributes):**
```json
["Variable", {}, ["x"]]
```

**V4 format (structured TypeAttributes):**
```json
{
  "Variable": {
    "attributes": {
      "source": {
        "startLine": 10,
        "startColumn": 5,
        "endLine": 10,
        "endColumn": 8
      },
      "constraints": {},
      "extensions": {}
    },
    "name": "x"
  }
}
```

**TypeAttributes structure:**
```yaml
TypeAttributes:
  type: object
  properties:
    source:
      $ref: "#/definitions/SourceLocation"
      description: "Source code location where this type appears"
    constraints:
      type: object
      description: "Type constraints (e.g., type class constraints)"
    extensions:
      type: object
      description: "Tool-specific extensions and metadata"
```

#### ValueAttributes

All value expressions use structured `ValueAttributes`:

**ValueAttributes structure:**
```yaml
ValueAttributes:
  type: object
  properties:
    source:
      $ref: "#/definitions/SourceLocation"
      description: "Source code location"
    inferredType:
      $ref: "#/definitions/Type"
      description: "Type inferred by the type checker"
    extensions:
      type: object
      description: "Tool-specific metadata"
```

#### SourceLocation

Structured source location tracking:

```yaml
SourceLocation:
  type: object
  required: ["startLine", "startColumn", "endLine", "endColumn"]
  properties:
    startLine: { type: integer }
    startColumn: { type: integer }
    endLine: { type: integer }
    endColumn: { type: integer }
```

**Benefits:**
- **Precise error reporting**: Exact source locations for type errors
- **IDE integration**: Better tooling support (go-to-definition, hover info)
- **Type information**: Inferred types available in IR for optimization
- **Extensibility**: Custom tooling can add metadata without breaking schema

---

### 2. Canonical String Formats

V4 introduces compact string representations for Names, Paths, and FQNames as an alternative to arrays.

#### Name

**Array format (V3 and V4):**
```json
["value", "in", "u", "s", "d"]
```

**String format (V4 only):**
```json
"value-in-USD"
```

**Pattern**: Segments joined by hyphens. A lowercase segment is a word; an uppercase segment is an initialism. A legacy array collapses each run of two or more single-letter words into one initialism on decode:
```json
["value", "in", "u", "s", "d"]  ↔  "value-in-USD"
["get", "h", "t", "m", "l"]     ↔  "get-HTML"
```

See the [naming specification](../../../draft/names.md) for the full grammar and the document-tree filename escape.

#### Path

**Array format:**
```json
[["morphir"], ["s", "d", "k"], ["list"]]
```

**String format (V4 only):**
```json
"morphir/SDK/list"
```

**Pattern**: Names joined by `/` separators.

#### FQName (Fully Qualified Name)

**Array format:**
```json
[
  [["morphir"], ["s", "d", "k"]],  // package
  [["list"]],                       // module
  ["map"]                           // name
]
```

**String format (V4 only):**
```json
"morphir/SDK:list#map"
```

**Pattern**: `package:module#name` where:
- Package and module are paths (with `/` separators)
- `:` separates package from module
- `#` separates module from name

**Benefits:**
- **More compact**: Reduces file size by ~30% in typical IR files
- **More readable**: Easier for humans to read and write
- **Faster parsing**: String parsing is faster than array traversal
- **Better error messages**: Easier to print readable references

---

### 3. Type and Value Shorthand

V4 supports compact shorthand notation for types and values when attributes are empty/null.

#### Type Shorthand

```json
// Variable
"a"                                    // shorthand
{ "Variable": { "name": "a" } }        // expanded (attributes first)
{ "Variable": { "attributes": {}, "name": "a" } }

// Simple reference (no type args)
"morphir/SDK:basics#int"                           // shorthand
{ "Reference": { "fqname": "morphir/SDK:basics#int" } }  // canonical

// Parameterized type: List Int
{ "Reference": ["morphir/SDK:list#list", "morphir/SDK:basics#int"] }      // canonical

// Nested: List (Maybe Int)
{ "Reference": ["morphir/SDK:list#list", { "Reference": ["morphir/SDK:maybe#maybe", "morphir/SDK:basics#int"] }] }

// Mixed: Result String a (variable as type arg)
{ "Reference": ["morphir/SDK:result#result", "morphir/SDK:string#string", "a"] }

// Tuple: (Int, String)
["morphir/SDK:basics#int", "morphir/SDK:string#string"]   // shorthand
{ "Tuple": ["morphir/SDK:basics#int", "morphir/SDK:string#string"] }   // canonical
```

**Disambiguation Logic:**
- If string contains `:` and `#` → FQName reference
- If string (no special chars) → Variable name
- If array → Tuple type (each element is a type)
- If object → Canonical wrapper object format

A parameterized reference always carries the `Reference` wrapper. A bare array is never a reference: a tuple of two plain types and a reference with one argument would otherwise have the same shape.

#### Value Shorthand

V4 also supports compact shorthand for value expressions when attributes are empty.

```json
// Boolean & Numbers
true                                   // shorthand for BoolLiteral
42                                     // shorthand for IntegerLiteral

// References & Variables
"morphir/SDK:basics#add"               // shorthand for Reference
"x"                                    // shorthand for Variable

// Lists
[1, 2, 3]                              // shorthand for List of Literals
["x", "y", "z"]                        // shorthand for List of Variables
```

**Disambiguation Logic:**
- If string contains `:` and `#` → FQName reference
- If string (no special chars) → Variable name
- If boolean/number → Literal
- If array → List value (decision 0009; a Tuple always carries its wrapper)
- If object → Canonical wrapper object format

#### Ultra-compact Patterns

Similarly, **LiteralPattern** supports direct primitive values for maximum ergonomics:

```json
{ "LiteralPattern": 42 }                // ultra-compact
{ "LiteralPattern": { "IntegerLiteral": 42 } } // compact/canonical
```

---

### 4. Embedded Documentation

V4 supports inline documentation for types and values within module definitions.

**Example:**
```json
{
  "types": {
    "user-ID": {
      "access": "Public",
      "doc": "Unique identifier for a user in the system",
      "TypeAliasDefinition": {
        "typeParams": [],
        "typeExp": "morphir/SDK:string#string"
      }
    }
  }
}
```

Modules key their types and values by canonical name. The `doc` member is placed first beside the variant (decision 0010). The nested `{ "doc": ..., "value": ... }` wrapper is accepted on input for one release and reported as `legacy_spelling` (decision 0006).

**Benefits:**
- **Self-documenting IR**: Documentation travels with code
- **Better code generation**: Generated code can include doc comments
- **API documentation**: Automatic API doc generation from IR

---

### 5. New Type Constructs

#### IncompleteTypeDefinition

For handling incomplete or broken type definitions during refactoring or best-effort code generation.

**Structure:**
```gleam
IncompleteTypeDefinition(
  params: List(TypeVariable),
  incompleteness: Incompleteness,
  partial_body: Option(Type(attributes))
)
```

**Incompleteness reasons:**
- **Hole**: Reference to something deleted/renamed
  - `UnresolvedReference`: Target FQName doesn't exist
  - `DeletedDuringRefactor`: Removed during refactoring
  - `TypeMismatch`: Type error
- **Draft**: Author-marked work-in-progress

**Example:**
```json
{
  "IncompleteTypeDefinition": {
    "params": ["a"],
    "incompleteness": {
      "Hole": {
        "reason": {
          "UnresolvedReference": {
            "target": "my-org/project:domain#missing-type"
          }
        }
      }
    }
  }
}
```

**Use cases:**
- Best-effort code generation when dependencies are incomplete
- Incremental refactoring with partial type information
- Preserving IR structure despite compilation errors

---

### 6. New Value Expressions

#### Hole

Represents an incomplete or broken value expression.

**Structure:**
```gleam
Hole(
  attributes: attributes,
  reason: HoleReason,
  expected_type: Option(Type(attributes))
)
```

**Example:**
```json
{
  "Hole": {
    "reason": {
      "UnresolvedReference": {
        "target": "my-org/project:module#deleted-function"
      }
    },
    "expectedType": "morphir/SDK:basics#int"
  }
}
```

**Use cases:**
- Best-effort generation when references are broken
- Preserving partial IR during refactoring
- Marking incomplete implementations

Native and external operations are definition bodies, not expressions (decision 0008); see section 7.

---

### 7. New Value Definition Bodies

In addition to the existing `ExpressionBody` (normal IR body), V4 introduces three new value definition body types:

#### NativeBody

For native/builtin operations with no IR implementation.

**Structure:**
```gleam
NativeBody(
  input_types: List(#(Name, Type(attributes))),
  output_type: Type(attributes),
  native_info: NativeInfo
)
```

**Example:**
```json
{
  "NativeBody": {
    "inputTypes": {
      "a": "morphir/SDK:basics#int",
      "b": "morphir/SDK:basics#int"
    },
    "outputType": "morphir/SDK:basics#int",
    "nativeInfo": {
      "hint": { "Arithmetic": {} }
    }
  }
}
```

#### ExternalBody

For external FFI definitions.

**Structure:**
```gleam
ExternalBody(
  input_types: List(#(Name, Type(attributes))),
  output_type: Type(attributes),
  externals: List(ExternalBinding),
  body: Option(Value(attributes))
)

ExternalBinding(
  target_platform: String,
  external_name: String
)
```

**Example:**
```json
{ "ExternalBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "externals": [{ "targetPlatform": "erlang", "externalName": "math:abs" }, { "targetPlatform": "javascript", "externalName": "Math.abs" }], "body": { "Variable": "x" } } }
```

The single-binding spelling with top-level `externalName`/`targetPlatform` is accepted for one release (decision 0006).

#### IncompleteBody

For incomplete value definitions.

**Structure:**
```gleam
IncompleteBody(
  input_types: List(#(Name, Type(attributes))),
  output_type: Option(Type(attributes)),
  incompleteness: Incompleteness,
  partial_body: Option(Value(attributes))
)
```

---

### 8. Literal Changes

#### IntegerLiteral (renamed from WholeNumberLiteral)

**V3:**
```json
["WholeNumberLiteral", 42]
```

**V4:**
```json
{ "IntegerLiteral": 42 }
```

The expanded `{ "IntegerLiteral": { "value": 42 } }` form is accepted on input.

**Reason**: "Whole number" traditionally means non-negative integers, but Morphir supports negative integers. "IntegerLiteral" is more accurate.

**Migration**: Decoders should accept both `WholeNumberLiteral` and `IntegerLiteral` for backwards compatibility. Encoders should output `IntegerLiteral`.

#### DocumentLiteral (new)

```json
{ "DocumentLiteral": { "name": "Alice", "age": 30, "tags": ["admin", "user"], "metadata": null } }
```

The payload is the document itself; there is no `{ "value": ... }` spelling. Number lexemes are preserved. A document cannot be pattern matched. Typed `morphir/SDK:document#document` (decision 0013).

---

### 9. Permissive Input, Canonical Output Policy

V4 establishes a clear **permissive input, canonical output** policy:

- **Decoders** accept multiple formats for backwards compatibility and flexibility
- **Encoders** output only the canonical format for consistency

This applies to all V4 constructs. The table below summarizes key formats:

| Construct | Canonical Output | Also Accepted |
|-----------|-----------------|---------------|
| **Access** | `"Public"`, `"Private"` | `"public"`, `"private"`, `"pub"` |
| **AccessControlled** | `{ "Public": {...} }` | `{ "pub": {...} }`, `{ "access": "Public", "value": {...} }` |
| **ReferenceType (no args)** | `"morphir/SDK:basics#int"` | `{ "Reference": "..." }`, `{ "Reference": { "fqname": "..." } }` |
| **ReferenceType (with args)** | `{ "Reference": ["fqname", t1, ...] }` | `{ "Reference": { "fqname": "...", "args": [...] } }` |
| **TupleType** | `{ "Tuple": [t1, t2, ...] }` | `[t1, t2, ...]`, `{ "Tuple": { "elements": [...] } }` |
| **TuplePattern** | `{ "TuplePattern": [p1, p2, ...] }` | `[p1, p2, ...]`, `{ "TuplePattern": { "patterns": [...] } }` |
| **TupleValue** | `{ "Tuple": [v1, v2, ...] }` | `{ "Tuple": { "elements": [...] } }` (NO bare arrays) |
| **ListValue** | `{ "List": [v1, v2, ...] }` | `{ "List": { "items": [...] } }` (NO bare arrays) |
| **Literals** | `{ "IntegerLiteral": 42 }` | `{ "IntegerLiteral": { "value": 42 } }`, `{ "WholeNumberLiteral": 42 }` |

:::note Design Rationale
- **TupleType** allows bare arrays because ReferenceType does NOT (avoiding ambiguity)
- **TupleValue/ListValue** do NOT allow bare arrays because they would be ambiguous with each other
- **Access abbreviations** like `"pub"` improve ergonomics for hand-written IR
:::

---

### 10. JSON Representation Changes

V4 moves from **tagged arrays** to **wrapper objects** for the canonical format:

**V3 (tagged array):**
```json
["Apply", {}, ["Reference", {}, fqName], ["Literal", {}, literal]]
```

**V4 (wrapper object):**
```json
{
  "Apply": {
    "function": { "Reference": "..." },
    "argument": { "Literal": { "IntegerLiteral": 1 } }
  }
}
```

**Benefits:**
- More readable and self-documenting
- Easier to work with in JSON-based tools
- Better TypeScript/JSON Schema integration
- Clearer field names

**Note**: V4 decoders **must accept both formats** for backwards compatibility:
- Wrapper object (v4 canonical)
- Tagged array with capitalized tags (v2/v3)
- Tagged array with lowercase tags (v1)

---

---

### 11. Structured Annotations

V4 introduces a first-class annotation system for attaching high-level semantic metadata (like `@deprecated`, `@stable`, or `@jsonName`) to signature specifications.

Unlike attributes (used for implementation-level metadata like source locations), annotations are intended for consumers of the IR and support both a compact string shorthand and a canonical object format.

**Compact Shorthand:**
```json
"annotations": [
  "morphir/SDK:annotations#stable",
  "my-org/sdk:annotations#deprecated:Use new-version instead"
]
```

**Canonical Object:**
```json
"annotations": [
  {
    "name": "my-org/sdk:annotations#author",
    "arguments": [
      { "name": "name", "value": { "Literal": { "StringLiteral": "Damian" } } }
    ]
  }
]
```

**Benefits:**
- **Semantic Metadata**: Attach domain-specific hints for downstream tools
- **API Life-cycle**: First-class support for deprecations and stability markers
- **Improved Code Generation**: Use annotations to drive platform-specific code generation patterns

---

## Benefits Summary

### For Tool Developers

1. **Precise source locations**: Build better error messages and IDE features
2. **Type information**: Leverage inferred types for optimization
3. **Extensibility**: Add custom metadata via `extensions` without breaking schema
4. **Easier parsing**: String formats and wrapper objects are more ergonomic
5. **Best-effort generation**: Handle incomplete code gracefully with Holes

### For Users

1. **Better error messages**: Exact line/column error reporting
2. **Inline documentation**: API docs embedded in IR
3. **Smaller files**: String formats reduce IR file size
4. **Incremental refactoring**: Work with incomplete code during refactoring

### For Language Designers

1. **Native operations**: Represent platform builtins without fake IR bodies
2. **FFI support**: First-class external function calls
3. **Incomplete code**: Support for drafts and holes enables better tooling
4. **Better semantics**: Clearer distinction between IR expressions and platform operations

---

## Migration from Version 3

To migrate from V3 to V4:

1. **Convert representation**: Move from tagged arrays to wrapper objects
2. **Convert attributes**: Transform generic attributes to TypeAttributes/ValueAttributes
3. **Use string formats**: Optionally adopt canonical string format for Names/Paths/FQNames
4. **Rename literals**: `WholeNumberLiteral` → `IntegerLiteral`
5. **Add documentation**: Embed docs where appropriate
6. **Mark incomplete code**: Use Hole/Native/External for non-standard code

See the [Migration Guide](../migration-guide/) for detailed instructions.

---

## Backward Compatibility

V4 decoders **must be permissive** and accept:
- V4 wrapper object format (canonical)
- V3 tagged arrays with capitalized tags
- V2 tagged arrays with mixed capitalization
- V1 tagged arrays with lowercase tags

V4 encoders **should prefer**:
- Wrapper object format for canonical output
- Shorthand notation when attributes are empty
- String format for Names/Paths/FQNames for compactness

V4 IR can be downgraded to V3 with **information loss**:

**Lost in V4 → V3:**
- Type constraints
- Inferred type information
- Inline documentation
- Hole/Native/External constructs (must be transformed or removed)
- IncompleteTypeDefinition and IncompleteBody

See [Migration Guide - V4 → V3](../migration-guide/#v4--v3) for details.

---

## Recommendation

**Version 4 is recommended for all new Morphir projects** due to its enhanced expressiveness, better tooling support, clearer semantics, and support for incomplete code during development and refactoring.

---

## See Also

- [Version 4 Schema](/schemas/morphir-ir-v4.yaml)
- [Migration Guide](../migration-guide/)
- [Version 3 Documentation](../v3/)
- [Morphir IR Specification](../../morphir-ir-specification/)
- [Design Draft - Values](../../../../design/draft/ir/values/)
- [Design Draft - Types](../../../../design/draft/ir/types/)
