---
title: "IR Version Migration Guide"
linkTitle: "Migration Guide"
weight: 10
description: "Complete guide for migrating between Morphir IR schema versions"
---

# Morphir IR Version Migration Guide

This guide provides detailed instructions for converting Morphir IR between different schema versions (v1, v2, v3, and v4).

## Table of Contents

- [Overview](#overview)
- [Version Comparison Matrix](#version-comparison-matrix)
- [Forward Migration (Upgrading)](#forward-migration-upgrading)
  - [V1 → V2](#v1--v2)
  - [V2 → V3](#v2--v3)
  - [V3 → V4](#v3--v4)
- [Backward Migration (Downgrading)](#backward-migration-downgrading)
  - [V4 → V3](#v4--v3)
  - [V3 → V2](#v3--v2)
  - [V2 → V1](#v2--v1)
- [Lossy Conversions](#lossy-conversions)
- [Migration Tools](#migration-tools)

## Overview

Morphir IR has evolved through four major versions, each introducing improvements to consistency, expressiveness, and tooling support:

- **V1**: Original format with all lowercase tags and object-based module structure
- **V2**: Partial capitalization (types capitalized, values lowercase) and array-based module structure
- **V3**: Full capitalization for consistency across all constructs
- **V4**: Explicit attribute types and additional value expressions

## Version Comparison Matrix

| Feature | V1 | V2 | V3 | V4 |
|---------|----|----|----|----|
| Distribution tag | `"library"` | `"Library"` | `"Library"` | `"Library"` |
| Access control | `"public"`, `"private"` | `"Public"`, `"Private"` | `"Public"`, `"Private"` | `"Public"`, `"Private"` |
| Type tags | lowercase | **Capitalized** | **Capitalized** | **Capitalized** |
| Value tags | lowercase | lowercase | **Capitalized** | **Capitalized** |
| Pattern tags | lowercase | lowercase | **Capitalized** | **Capitalized** |
| Literal tags | lowercase | lowercase | **Capitalized** | **Capitalized** |
| Module structure | Object `{name, def}` | Array `[name, AC]` | Array `[name, AC]` | Array `[name, AC]` |
| Attributes | Generic `a` | Generic `a` | Generic `a` | **TypeAttributes / ValueAttributes** |
| Name format | Array only | Array only | Array only | **String or Array** |
| Path format | Array only | Array only | Array only | **String or Array** |
| FQName format | Array only | Array only | Array only | **String or Array** |
| Documentation | No | No | No | **Embedded doc fields** |
| New values | - | - | - | **Constructor, List, FieldFunction, LetRecursion, Destructure, UpdateRecord, Unit** |
| Source location | In attributes | In attributes | In attributes | **Structured in attributes** |

## Forward Migration (Upgrading)

### V1 → V2

Migrating from V1 to V2 involves capitalizing distribution, access control, and type tags, plus restructuring modules.

#### Changes Required

##### 1. Distribution Tag
```diff
- ["library", packageName, dependencies, packageDef]
+ ["Library", packageName, dependencies, packageDef]
```

##### 2. Access Control
```diff
- "public"  → "Public"
- "private" → "Private"
```

##### 3. Module Structure
Transform from object-based to array-based:

**V1 format:**
```json
{
  "modules": [
    {
      "name": [["my"], ["module"]],
      "def": ["public", { "types": {...}, "values": {...} }]
    }
  ]
}
```

**V2 format:**
```json
{
  "modules": [
    [
      [["my"], ["module"]],
      {
        "access": "Public",
        "value": { "types": {...}, "values": {...} }
      }
    ]
  ]
}
```

##### 4. Type Tags
Capitalize all type tags:

```diff
- ["variable", attrs, name]
+ ["Variable", attrs, name]

- ["reference", attrs, fqName, typeArgs]
+ ["Reference", attrs, fqName, typeArgs]

- ["tuple", attrs, elementTypes]
+ ["Tuple", attrs, elementTypes]

- ["record", attrs, fields]
+ ["Record", attrs, fields]

- ["function", attrs, argType, returnType]
+ ["Function", attrs, argType, returnType]
```

##### 5. Type Specifications
```diff
- ["type_alias_specification", typeParams, type]
+ ["TypeAliasSpecification", typeParams, type]

- ["custom_type_specification", typeParams, constructors]
+ ["CustomTypeSpecification", typeParams, constructors]

- ["opaque_type_specification", typeParams]
+ ["OpaqueTypeSpecification", typeParams]
```

#### Migration Algorithm

```python
def migrate_v1_to_v2(ir_v1):
    # 1. Update distribution tag
    ir_v2 = {
        "formatVersion": 2,
        "distribution": ["Library"] + ir_v1["distribution"][1:]
    }

    # 2. Transform modules from object to array format
    package_def = ir_v2["distribution"][3]
    package_def["modules"] = [
        [
            module["name"],
            {
                "access": capitalize_access(module["def"][0]),
                "value": module["def"][1]
            }
        ]
        for module in package_def["modules"]
    ]

    # 3. Recursively capitalize type tags
    capitalize_type_tags(ir_v2)

    return ir_v2
```

#### Data Loss: **NONE**

All V1 constructs can be represented in V2 without loss of information.

---

### V2 → V3

Migrating from V2 to V3 involves capitalizing all remaining tags (values, patterns, literals).

#### Changes Required

##### 1. Value Expression Tags

Capitalize all value tags and convert snake_case to PascalCase:

```diff
- ["apply", attrs, function, arg]
+ ["Apply", attrs, function, arg]

- ["lambda", attrs, pattern, body]
+ ["Lambda", attrs, pattern, body]

- ["let_definition", attrs, name, def, inExpr]
+ ["LetDefinition", attrs, name, def, inExpr]

- ["if_then_else", attrs, condition, then, else]
+ ["IfThenElse", attrs, condition, then, else]

- ["pattern_match", attrs, value, cases]
+ ["PatternMatch", attrs, value, cases]

- ["literal", attrs, literal]
+ ["Literal", attrs, literal]

- ["variable", attrs, name]
+ ["Variable", attrs, name]

- ["reference", attrs, fqName]
+ ["Reference", attrs, fqName]

- ["constructor", attrs, fqName]
+ ["Constructor", attrs, fqName]

- ["tuple", attrs, elements]
+ ["Tuple", attrs, elements]

- ["list", attrs, elements]
+ ["List", attrs, elements]

- ["record", attrs, fields]
+ ["Record", attrs, fields]

- ["field", attrs, target, fieldName]
+ ["Field", attrs, target, fieldName]

- ["field_function", attrs, fieldName]
+ ["FieldFunction", attrs, fieldName]

- ["let_recursion", attrs, definitions, inExpr]
+ ["LetRecursion", attrs, definitions, inExpr]

- ["destructure", attrs, pattern, value, inExpr]
+ ["Destructure", attrs, pattern, value, inExpr]

- ["update_record", attrs, target, updates]
+ ["UpdateRecord", attrs, target, updates]

- ["unit", attrs]
+ ["Unit", attrs]
```

##### 2. Pattern Tags

```diff
- ["wildcard_pattern", attrs]
+ ["WildcardPattern", attrs]

- ["as_pattern", attrs, pattern, name]
+ ["AsPattern", attrs, pattern, name]

- ["tuple_pattern", attrs, patterns]
+ ["TuplePattern", attrs, patterns]

- ["constructor_pattern", attrs, fqName, patterns]
+ ["ConstructorPattern", attrs, fqName, patterns]

- ["empty_list_pattern", attrs]
+ ["EmptyListPattern", attrs]

- ["head_tail_pattern", attrs, head, tail]
+ ["HeadTailPattern", attrs, head, tail]

- ["literal_pattern", attrs, literal]
+ ["LiteralPattern", attrs, literal]

- ["unit_pattern", attrs]
+ ["UnitPattern", attrs]
```

##### 3. Literal Tags

```diff
- ["bool_literal", value]
+ ["BoolLiteral", value]

- ["char_literal", value]
+ ["CharLiteral", value]

- ["string_literal", value]
+ ["StringLiteral", value]

- ["whole_number_literal", value]
+ ["WholeNumberLiteral", value]

- ["float_literal", value]
+ ["FloatLiteral", value]

- ["decimal_literal", value]
+ ["DecimalLiteral", value]
```

#### Migration Algorithm

```python
def migrate_v2_to_v3(ir_v2):
    ir_v3 = copy.deepcopy(ir_v2)
    ir_v3["formatVersion"] = 3

    # Recursively capitalize value, pattern, and literal tags
    capitalize_all_tags(ir_v3)

    return ir_v3

def capitalize_all_tags(node):
    if isinstance(node, list) and len(node) > 0:
        # Capitalize tag (first element)
        if isinstance(node[0], str):
            node[0] = to_pascal_case(node[0])
        # Recurse into children
        for item in node[1:]:
            capitalize_all_tags(item)
    elif isinstance(node, dict):
        for value in node.values():
            capitalize_all_tags(value)

def to_pascal_case(snake_case_str):
    # Convert snake_case to PascalCase
    return ''.join(word.capitalize() for word in snake_case_str.split('_'))
```

#### Data Loss: **NONE**

All V2 constructs can be represented in V3 without loss of information.

---

### V3 → V4

Migrating from V3 to V4 involves replacing generic attributes with explicit attribute types and optionally converting to canonical string formats.

#### Changes Required

##### 1. Explicit Attribute Types

Replace generic attributes `a` with structured attributes:

**Type Attributes:**
```diff
- ["Variable", attrs, name]
+ ["Variable", { "source": {...}, "constraints": {...}, "extensions": {...} }, name]

Where attrs is a generic value (often {}) in V3, but in V4 is a structured object:
{
  "source": {
    "startLine": int,
    "startColumn": int,
    "endLine": int,
    "endColumn": int
  },
  "constraints": { ... },  // Optional
  "extensions": { ... }    // Optional
}
```

**Value Attributes:**
```diff
- ["Apply", attrs, function, arg]
+ ["Apply", { "source": {...}, "inferredType": {...}, "extensions": {...} }, function, arg]

Where attrs becomes:
{
  "source": {
    "startLine": int,
    "startColumn": int,
    "endLine": int,
    "endColumn": int
  },
  "inferredType": Type,    // Optional
  "extensions": { ... }    // Optional
}
```

##### 2. Canonical String Formats (Optional)

V4 supports compact string representations for Names, Paths, and FQNames:

**Names:**
```diff
Array format (both V3 and V4):
["value", "in", "u", "s", "d"]

String format (V4 only):
"value-in-u-s-d"
```

**Paths:**
```diff
Array format:
[["morphir"], ["s", "d", "k"]]

String format (V4 only):
"morphir/s-d-k"
```

**FQNames:**
```diff
Array format:
[
  [["morphir"], ["s", "d", "k"]],  // package
  [["list"]],                       // module
  ["map"]                           // name
]

String format (V4 only):
"morphir/s-d-k:list#map"
```

##### 3. Documentation Fields

V4 allows embedded documentation in module and value definitions:

```json
{
  "types": [
    [
      ["user", "id"],
      {
        "access": "Public",
        "value": {
          "doc": "Unique identifier for a user",
          "value": ["TypeAliasSpecification", [], ["Reference", {}, "morphir/sdk:string#String", []]]
        }
      }
    ]
  ]
}
```

##### 4. New Value Expressions

V4 introduces several new value expression types. If your V3 IR contains workarounds for these, they can be replaced:

- **Constructor**: Direct reference to a constructor without application
- **List**: Native list literal (alternative to SDK List construction)
- **FieldFunction**: Direct field accessor function
- **LetRecursion**: Mutual recursion support
- **Destructure**: Pattern-based destructuring
- **UpdateRecord**: Record update syntax
- **Unit**: Explicit unit value

#### Migration Algorithm

```python
def migrate_v3_to_v4(ir_v3, preserve_source_info=True):
    ir_v4 = {
        "formatVersion": 4,
        "distribution": migrate_distribution(ir_v3["distribution"])
    }

    return ir_v4

def migrate_attributes(attrs, is_type_attr=True):
    """Convert generic attributes to structured attributes."""
    if is_type_attr:
        return {
            "source": extract_source_location(attrs) if preserve_source_info else None,
            "constraints": {},
            "extensions": {}
        }
    else:  # Value attributes
        return {
            "source": extract_source_location(attrs) if preserve_source_info else None,
            "inferredType": None,  # Could be populated by type inference
            "extensions": {}
        }

def migrate_name_to_string(name_array):
    """Optionally convert Name from array to string format."""
    return "-".join(name_array)

def migrate_path_to_string(path_array):
    """Optionally convert Path from array to string format."""
    return "/".join(migrate_name_to_string(name) for name in path_array)

def migrate_fqname_to_string(fqname_array):
    """Optionally convert FQName from array to string format."""
    pkg, mod, name = fqname_array
    return f"{migrate_path_to_string(pkg)}:{migrate_path_to_string(mod)}#{migrate_name_to_string(name)}"
```

#### Data Loss: **POSSIBLE**

**Lossy scenarios:**

1. **Attributes without source information**: If V3 attributes are empty objects `{}`, V4's structured attributes may need placeholder or null values
2. **Custom attribute data**: Any custom data stored in V3 generic attributes may not fit the V4 structure (should be moved to `extensions`)
3. **Type inference**: V4's `inferredType` in ValueAttributes is typically populated by a type checker, not available from V3

**Recommendation**: Preserve V3 attributes in V4's `extensions` field for full round-trip compatibility.

---

## Backward Migration (Downgrading)

Backward migration may be necessary for compatibility with older tooling. Some migrations are lossy.

### V4 → V3

#### Changes Required

##### 1. Flatten Attributes

Convert structured attributes back to generic form:

```diff
V4 TypeAttributes:
{
  "source": { "startLine": 10, "startColumn": 5, "endLine": 10, "endColumn": 20 },
  "constraints": {},
  "extensions": { "customKey": "customValue" }
}

V3 generic attributes:
{
  "source": { "startLine": 10, "startColumn": 5, "endLine": 10, "endColumn": 20 },
  "customKey": "customValue"
}
```

##### 2. Convert Canonical Strings to Arrays

If using V4's string format, convert back to arrays:

```python
def string_to_name(name_str):
    """Convert 'value-in-usd' to ['value', 'in', 'usd']"""
    return name_str.split('-')

def string_to_path(path_str):
    """Convert 'morphir/sdk' to [['morphir'], ['sdk']]"""
    return [string_to_name(segment) for segment in path_str.split('/')]

def string_to_fqname(fqname_str):
    """Convert 'morphir/sdk:list#map' to [[['morphir'], ['sdk']], [['list']], ['map']]"""
    pkg_mod, name = fqname_str.split('#')
    pkg, mod = pkg_mod.split(':')
    return [string_to_path(pkg), string_to_path(mod), string_to_name(name)]
```

##### 3. Remove V4-Only Constructs

V4 introduces new value expressions not present in V3. These must be transformed:

**Constructor** → **Reference**:
```diff
- ["Constructor", attrs, fqName]
+ ["Reference", attrs, fqName]
```

**List** → **SDK List construction**:
```diff
- ["List", attrs, [elem1, elem2, elem3]]
+ Multiple Apply nodes calling List.singleton and List.append
```

**FieldFunction** → **Lambda with Field**:
```diff
- ["FieldFunction", attrs, fieldName]
+ ["Lambda", attrs, ["AsPattern", attrs, ["WildcardPattern", attrs], ["x"]],
    ["Field", attrs, ["Variable", attrs, ["x"]], fieldName]]
```

**LetRecursion** → **Multiple LetDefinition** (if possible):
```diff
- ["LetRecursion", attrs, [[name1, def1], [name2, def2]], inExpr]
+ Attempt to order definitions to break mutual recursion
  (May not be possible for all cases)
```

**Destructure** → **PatternMatch**:
```diff
- ["Destructure", attrs, pattern, value, inExpr]
+ ["PatternMatch", attrs, value, [[pattern, inExpr]]]
```

**UpdateRecord** → **Record construction**:
```diff
- ["UpdateRecord", attrs, target, [[field1, value1], [field2, value2]]]
+ ["Record", attrs, [
    [field1, value1],
    [field2, value2],
    ... all other fields copied from target ...
  ]]
```

**Unit** → **Tuple with zero elements**:
```diff
- ["Unit", attrs]
+ ["Tuple", attrs, []]
```

##### 4. Remove Documentation Fields

V4 allows inline documentation which V3 doesn't support:

```python
def remove_doc_wrappers(type_or_value):
    """Remove V4 doc wrappers from types/values."""
    if isinstance(type_or_value, dict) and "doc" in type_or_value:
        return type_or_value["value"]
    return type_or_value
```

#### Data Loss: **POSSIBLE**

**Lossy scenarios:**

1. **Source location precision**: V4's structured SourceLocation in attributes may be lost if V3 uses unstructured attributes
2. **Type constraints**: V4's `TypeAttributes.constraints` has no V3 equivalent
3. **Inferred types**: V4's `ValueAttributes.inferredType` has no V3 equivalent
4. **Documentation**: Inline `doc` fields are lost
5. **Mutual recursion**: `LetRecursion` may not be expressible without mutual recursion (must fail or approximate)
6. **Record updates**: `UpdateRecord` must be expanded to full record reconstruction (verbose but equivalent)
7. **Extensions**: Custom data in `extensions` must be moved to generic attributes

---

### V3 → V2

#### Changes Required

##### 1. Decapitalize Value, Pattern, and Literal Tags

Reverse the V2→V3 capitalization:

```diff
+ ["apply", attrs, function, arg]
- ["Apply", attrs, function, arg]

+ ["lambda", attrs, pattern, body]
- ["Lambda", attrs, pattern, body]

+ ["wildcard_pattern", attrs]
- ["WildcardPattern", attrs]

+ ["bool_literal", value]
- ["BoolLiteral", value]
```

#### Migration Algorithm

```python
def migrate_v3_to_v2(ir_v3):
    ir_v2 = copy.deepcopy(ir_v3)
    ir_v2["formatVersion"] = 2

    # Recursively decapitalize value, pattern, and literal tags
    decapitalize_value_tags(ir_v2)

    return ir_v2

def decapitalize_value_tags(node):
    if isinstance(node, list) and len(node) > 0:
        tag = node[0]
        if isinstance(tag, str) and is_value_or_pattern_tag(tag):
            node[0] = to_snake_case(tag)
        for item in node[1:]:
            decapitalize_value_tags(item)
    elif isinstance(node, dict):
        for value in node.values():
            decapitalize_value_tags(value)

def to_snake_case(pascal_case_str):
    # Convert PascalCase to snake_case
    import re
    return re.sub(r'(?<!^)(?=[A-Z])', '_', pascal_case_str).lower()
```

#### Data Loss: **NONE**

All V3 constructs can be represented in V2 without loss.

---

### V2 → V1

#### Changes Required

##### 1. Decapitalize Distribution and Access Control

```diff
+ ["library", ...]
- ["Library", ...]

+ "public", "private"
- "Public", "Private"
```

##### 2. Decapitalize Type Tags

```diff
+ ["variable", attrs, name]
- ["Variable", attrs, name]

+ ["type_alias_specification", ...]
- ["TypeAliasSpecification", ...]
```

##### 3. Restructure Modules

Convert from array format back to object format:

```diff
V2 format:
[
  [["my"], ["module"]],
  { "access": "Public", "value": {...} }
]

V1 format:
{
  "name": [["my"], ["module"]],
  "def": ["public", {...}]
}
```

#### Migration Algorithm

```python
def migrate_v2_to_v1(ir_v2):
    ir_v1 = {
        "formatVersion": 1,
        "distribution": ["library"] + ir_v2["distribution"][1:]
    }

    # Transform modules from array to object format
    package_def = ir_v1["distribution"][3]
    package_def["modules"] = [
        {
            "name": module[0],
            "def": [
                decapitalize_access(module[1]["access"]),
                module[1]["value"]
            ]
        }
        for module in package_def["modules"]
    ]

    # Recursively decapitalize type tags
    decapitalize_type_tags(ir_v1)

    return ir_v1
```

#### Data Loss: **NONE**

All V2 constructs can be represented in V1 without loss.

---

## Lossy Conversions

### Summary Table

| Migration | Lossy? | What's Lost |
|-----------|--------|-------------|
| V1 → V2 | ❌ No | - |
| V2 → V3 | ❌ No | - |
| V3 → V4 | ⚠️ Possible | Generic attribute data (store in `extensions`) |
| V4 → V3 | ⚠️ Yes | Type constraints, inferred types, inline docs, V4-only value expressions |
| V3 → V2 | ❌ No | - |
| V2 → V1 | ❌ No | - |

### Detailed Lossy Scenarios

#### V3 → V4: Potential Loss

- **Custom attribute data**: If V3 uses attributes creatively (storing custom metadata), it must be migrated to V4's `extensions` field

**Mitigation**: Always populate `extensions` with V3 attribute data:

```python
v4_attrs = {
    "source": extract_source(v3_attrs),
    "extensions": v3_attrs  # Preserve everything
}
```

#### V4 → V3: Definite Loss

1. **Type constraints** (`TypeAttributes.constraints`)
   - **Lost**: Constraint information
   - **Mitigation**: Encode as comments or external metadata

2. **Inferred types** (`ValueAttributes.inferredType`)
   - **Lost**: Type inference results
   - **Mitigation**: Re-run type inference on V3

3. **Inline documentation** (`doc` fields)
   - **Lost**: Inline documentation strings
   - **Mitigation**: Extract to separate documentation files

4. **V4-only value expressions**:
   - **Constructor**: Convert to Reference (semantically equivalent)
   - **List**: Expand to SDK calls (verbose but equivalent)
   - **FieldFunction**: Expand to Lambda (equivalent)
   - **LetRecursion**: **Cannot always convert** (mutual recursion may be inexpressible)
   - **Destructure**: Convert to PatternMatch (equivalent)
   - **UpdateRecord**: Expand to full Record (verbose but equivalent)
   - **Unit**: Convert to empty Tuple (equivalent)

**Recommendation for LetRecursion**: If mutual recursion is essential, **migration will fail**. Otherwise, attempt topological sort to order definitions.

---

## Migration Tools

### Recommended Approach

1. **Use official Morphir tools** if available (check Morphir SDK for migration utilities)
2. **Validate before and after** migration using JSON Schema validation
3. **Test with round-trip** conversions when possible
4. **Preserve original** IR files before migration

### Validation

Each version has a JSON Schema for validation:

```bash
# Validate V1
jsonschema -i my-ir-v1.json schemas/v1/morphir-ir-v1.yaml

# Validate V4
jsonschema -i my-ir-v4.json schemas/v4/morphir-ir-v4.yaml
```

### Example Migration Script (V3 → V4)

```python
import json

def migrate_v3_to_v4_file(input_path, output_path):
    with open(input_path, 'r') as f:
        ir_v3 = json.load(f)

    ir_v4 = migrate_v3_to_v4(ir_v3)

    with open(output_path, 'w') as f:
        json.dump(ir_v4, f, indent=2)

    print(f"Migrated {input_path} → {output_path}")

# Usage
migrate_v3_to_v4_file("morphir-ir-v3.json", "morphir-ir-v4.json")
```

---

## Best Practices

1. **Always upgrade forward when possible**: V4 is the most expressive format
2. **Preserve source information**: Don't discard source locations during migration
3. **Use extensions for custom data**: Store tooling-specific data in `extensions` fields
4. **Document why downgrading**: If migrating backward, document the compatibility requirement
5. **Test thoroughly**: Validate that migrated IR produces equivalent behavior
6. **Version your IR files**: Include `formatVersion` in all IR files
7. **Use canonical formats in V4**: String representations are more compact and readable

---

## See Also

- [Schema Version 1](../v1/)
- [Schema Version 2](../v2/)
- [Schema Version 3](../v3/)
- [Schema Version 4](../v4/)
- [Morphir IR Specification](../../morphir-ir-specification/)
