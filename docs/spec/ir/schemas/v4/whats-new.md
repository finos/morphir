---
title: "What's New in Version 4"
linkTitle: "What's New"
weight: 1
description: "Changes and improvements in Morphir IR schema version 4"
---

# What's New in Version 4

Version 4 of the Morphir IR schema introduces explicit attribute types, canonical string formats, embedded documentation, and new constructs for handling incomplete code and native operations.

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
"value-in-u-s-d"
```

**Pattern**: Words joined by hyphens. Parenthesized words use `-(word)` syntax:
```json
["my", "add", "operator"]  ↔  "my-add-(operator)"
```

#### Path

**Array format:**
```json
[["morphir"], ["s", "d", "k"], ["list"]]
```

**String format (V4 only):**
```json
"morphir/s-d-k/list"
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
"morphir/s-d-k:list#map"
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
{ "Variable": { "name": "a" } }        // canonical

// Simple reference (no type args)
"morphir/sdk:basics#int"                           // shorthand
{ "Reference": { "fqname": "morphir/sdk:basics#int" } }  // canonical

// Parameterized type: List Int
["morphir/sdk:list#list", "morphir/sdk:basics#int"]      // shorthand

// Nested: List (Maybe Int)
["morphir/sdk:list#list", ["morphir/sdk:maybe#maybe", "morphir/sdk:basics#int"]]

// Mixed: Result String a (variable as type arg)
["morphir/sdk:result#result", "morphir/sdk:string#string", "a"]
```

**Disambiguation Logic:**
- If string contains `:` and `#` → FQName reference
- If string (no special chars) → Variable name
- If array → Parameterized type (first element is FQName, rest are type args)
- If object → Canonical wrapper object format

---

### 4. Embedded Documentation

V4 supports inline documentation for types and values within module definitions.

**Example:**
```json
{
  "types": [
    [
      ["user", "id"],
      {
        "access": "Public",
        "value": {
          "doc": "Unique identifier for a user in the system",
          "value": {
            "TypeAliasDefinition": {
              "body": "morphir/sdk:string#string"
            }
          }
        }
      }
    ]
  ]
}
```

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
    "expectedType": "morphir/sdk:basics#int"
  }
}
```

**Use cases:**
- Best-effort generation when references are broken
- Preserving partial IR during refactoring
- Marking incomplete implementations

#### Native

Represents a native platform operation with no IR body.

**Structure:**
```gleam
Native(
  attributes: attributes,
  fqname: FQName,
  native_info: NativeInfo
)
```

**NativeInfo:**
```gleam
NativeInfo(
  hint: NativeHint,          // Arithmetic, Comparison, StringOp, CollectionOp, PlatformSpecific
  description: Option(String)
)
```

**Example:**
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

**Use cases:**
- Representing SDK builtins (add, subtract, string operations)
- Platform-specific operations (database queries, HTTP calls)
- Operations that cannot be expressed in pure IR

#### External

Represents an external FFI call to another platform.

**Structure:**
```gleam
External(
  attributes: attributes,
  external_name: String,
  target_platform: String
)
```

**Example:**
```json
{
  "External": {
    "externalName": "calculateTaxRate",
    "targetPlatform": "JavaScript"
  }
}
```

**Use cases:**
- FFI calls to JavaScript, Python, etc.
- Integration with platform-specific libraries
- Interop with non-Morphir code

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
      "a": "morphir/sdk:basics#int",
      "b": "morphir/sdk:basics#int"
    },
    "outputType": "morphir/sdk:basics#int",
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
  external_name: String,
  target_platform: String
)
```

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
{ "IntegerLiteral": { "value": 42 } }
```

**Reason**: "Whole number" traditionally means non-negative integers, but Morphir supports negative integers. "IntegerLiteral" is more accurate.

**Migration**: Decoders should accept both `WholeNumberLiteral` and `IntegerLiteral` for backwards compatibility. Encoders should output `IntegerLiteral`.

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
| **ReferenceType (no args)** | `"morphir/sdk:basics#int"` | `{ "Reference": "..." }`, `{ "Reference": { "fqname": "..." } }` |
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
    "function": { "Reference": { "fqname": "..." } },
    "argument": { "Literal": { "literal": {...} } }
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
