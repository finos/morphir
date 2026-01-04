---
title: "What's New in Version 2"
linkTitle: "What's New"
weight: 1
description: "Changes and improvements in Morphir IR schema version 2"
---

# What's New in Version 2

Version 2 of the Morphir IR schema introduces partial capitalization and a new module structure, representing a significant evolution from version 1.

## Key Changes from Version 1

### Partial Capitalization

Version 2 introduces capitalization for distribution, access control, and type-related tags:

#### Capitalized Tags

**Distribution:**
- `"library"` → `"Library"`

**Access Control:**
- `"public"` → `"Public"`
- `"private"` → `"Private"`

**Type Tags:**
- `"variable"` → `"Variable"`
- `"reference"` → `"Reference"`
- `"tuple"` → `"Tuple"`
- `"record"` → `"Record"`
- `"extensible_record"` → `"ExtensibleRecord"`
- `"function"` → `"Function"`
- `"unit"` → `"Unit"`

**Type Specifications:**
- `"type_alias_specification"` → `"TypeAliasSpecification"`
- `"opaque_type_specification"` → `"OpaqueTypeSpecification"`
- `"custom_type_specification"` → `"CustomTypeSpecification"`
- `"derived_type_specification"` → `"DerivedTypeSpecification"`

**Type Definitions:**
- `"type_alias_definition"` → `"TypeAliasDefinition"`
- `"custom_type_definition"` → `"CustomTypeDefinition"`

#### Unchanged (Lowercase) Tags

**Value expressions** remain lowercase:
- `"apply"`, `"lambda"`, `"let_definition"`, `"if_then_else"`, etc.

**Patterns** remain lowercase:
- `"wildcard_pattern"`, `"as_pattern"`, `"constructor_pattern"`, etc.

**Literals** remain lowercase:
- `"bool_literal"`, `"string_literal"`, `"whole_number_literal"`, etc.

### New Module Structure

Version 2 changes how modules are represented in packages:

#### Version 1 Structure
```json
{
  "modules": [
    {
      "name": [["my"], ["module"]],
      "def": ["public", { ... }]
    }
  ]
}
```

#### Version 2 Structure
```json
{
  "modules": [
    [
      [["my"], ["module"]],
      {
        "access": "Public",
        "value": { ... }
      }
    ]
  ]
}
```

**Changes:**
- Modules are now represented as **arrays** instead of objects
- Structure changed from `{"name": ..., "def": ...}` to `[modulePath, accessControlled]`
- Access control uses the new `AccessControlled` wrapper with capitalized values

### Access Control Wrapper

Version 2 introduces a structured `AccessControlled` wrapper:

```yaml
AccessControlled:
  type: object
  required: ["access", "value"]
  properties:
    access:
      type: string
      enum: ["Public", "Private"]
    value:
      description: "The value being access controlled."
```

This provides a consistent way to manage visibility across types and values.

## Benefits

### Improved Clarity

- **Capitalized type tags** stand out more clearly in JSON structures
- **Structured access control** makes visibility explicit and consistent
- **Array-based module structure** is more compact and follows the pattern used elsewhere in the IR

### Better Type Safety

The structured `AccessControlled` wrapper provides:
- Explicit access level declaration
- Type-safe representation
- Easier validation

### Foundation for Version 3

Version 2 serves as a transition toward the fully capitalized format in version 3, making eventual migration easier.

## Migration from Version 1

To migrate from version 1 to version 2:

1. **Capitalize distribution tag**: `"library"` → `"Library"`
2. **Capitalize access control**: `"public"` → `"Public"`, `"private"` → `"Private"`
3. **Update module structure**: Convert `{"name": ..., "def": ...}` to array format
4. **Capitalize all type tags**: `"variable"` → `"Variable"`, `"reference"` → `"Reference"`, etc.
5. **Capitalize type specification and definition tags**

## Looking Forward

While version 2 introduces important improvements, **version 3 completes the capitalization** by extending it to value expressions, patterns, and literals. For new projects, consider using version 3 directly for maximum consistency.

## See Also

- [Version 2 Overview](../)
- [Full Schema](./full/)
- [Migration to Version 3](../v3/#migration-from-version-2)
- [Version 1 Documentation](../v1/)
