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
  - [Files written by CLIs before 0.4.0-alpha.7](#files-written-by-clis-before-040-alpha7)
  - [Format-version support tables and the renamed diagnostic](#format-version-support-tables-and-the-renamed-diagnostic)
  - [Document-tree layout in 0.4.0-beta.1](#document-tree-layout-in-040-beta1)
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

### Files written by CLIs before 0.4.0-alpha.7

Before the v4 vocabulary settled, the Rust CLI and some published examples wrote a handful of v4 member
names and shapes that differ from the ones the v4 schema and the Morphir Compatibility Kit (the
[MCK](https://github.com/finos/morphir/tree/main/spec/ir/mck)) pin as canonical. Release 0.4.0-alpha.7
decodes files carrying those older spellings, but reports a `legacy_spelling` warning at each place it
does so. Release 0.4.0-beta.1 keeps that window open. A later release closes it: the same spellings are then
refused as unknown members.

A `legacy_spelling` warning is a normal decode-time diagnostic, the same kind a CLI or binding reports for
any other v4 finding, pointed at the member's JSON pointer cursor. It means the member decoded successfully
under its old name, not that anything is wrong with the value — but the file should be rewritten (see
below) before the window closes. The MCK's `accepted warning=legacy_spelling` fences in `spec/ir/mck` are
the authoritative list of which spellings this covers; the tables here mirror them.

#### Renamed members

| Node | Old spelling | Canonical spelling |
| ---- | ------------ | ------------------- |
| any node | `attrs` | `attributes` |
| `Function` | `argumentType`, `arg` | `parameterType` |
| `Function` | `result` | `returnType` |
| `IfThenElse` | `thenBranch` | `then` |
| `IfThenElse` | `elseBranch` | `else` |
| `Field` | `subject` | `target` |
| `Field` | `fieldName` | `name` |
| `LetDefinition` | `valueName` | `name` |
| `LetDefinition` | `valueDefinition` | `definition` |
| `LetDefinition` | `inValue` | `in` |
| `ExternalBody` | `externalName`, `targetPlatform` (single pair) | `externals` (list) |

#### Structural changes, accepted with a warning

- A `Record` type or value that carries its field map directly under the wrapper, instead of under a
  `fields` member, decodes with a warning.
- A definition nested under a `value` member beside its `Public`/`Private` access tag, instead of
  flattened onto the wrapper, decodes with a warning.
- A `{ "doc", "value" }` wrapper, instead of a flattened `doc` member beside the variant it documents,
  decodes with a warning.

#### Refused outright, no window

Some pre-decision shapes are not old spellings of a current member; they no longer exist in v4 at all, so
there is nothing to accept even temporarily:

- The `Native` and `External` value expressions. In v4 these are definition bodies (`NativeBody`,
  `ExternalBody`), not value expressions.
- A Classic (v3) tagged array nested inside a version-4 document.

#### Rewriting a file before the window closes

`morphir migrate` reads a v4 file — accepting any legacy spellings above, with their warnings — and writes
it back out canonically:

```bash
morphir migrate <path/to/file> -o <path/to/file> --target-version v4
```

Writing to the same path as the input is safe: `morphir migrate` (`crates/morphir/src/commands/migrate.rs`)
never opens the output path directly. It encodes into a temporary file created beside it and only renames
that temporary file over the destination once encoding has finished, so the original content at the input
path is never truncated while it is still being read.

Run this on any file written by a pre-0.4.0-alpha.7 CLI, so it decodes without warnings and keeps
decoding after the window closes.

This vocabulary and its one-release window are decided in decisions 0004 to 0015: decision 0004 (record
fields under `fields`), decision 0006 (the member names and the window itself), decision 0007
(`parameterType`/`returnType`), decision 0008 (`Native`/`External` refused, `ExternalBody` as a list),
and decision 0010 (flattened `doc`).

---

### Format-version support tables and the renamed diagnostic

A reader no longer lists the exact releases it accepts. It declares a **support table**: a union of intervals
over release strings in Maven-style notation, such as the reference table `[3.0.0,3.1.0),[4.0.0,4.1.0)`. A patch
revision changes nothing a reader can observe, so a `4.0.0` reader now reads every `4.0.x` document, including
`4.0.1`, with no change to the file. A minor revision may change what a reader accepts, so `4.1.0` is still
refused.

The diagnostic for that refusal is renamed: `unsupported_format_version_revision` becomes
`unsupported_format_version_minor`, pairing with `unsupported_format_version_major`. The old code is pre-release
and has no alias, so any tooling or test that matched on it by string must be updated. Nothing in a migrated IR
file changes; only the reader's acceptance rule and the diagnostic code do. This is decided in decision 0016.

---

### Document-tree layout in 0.4.0-beta.1

A distribution can be stored as a directory of small files rather than one document. That layout — the
**document tree** — is specified on the [document-tree page](./v4/document-tree-files.md) and pinned by MCK
cases document-tree-0001 to 0009. Release 0.4.0-beta.1 makes the Rust CLI write and read the layout that
page describes. Trees written by earlier releases are refused rather than reinterpreted.

#### The canonical shape

```text
manifest.yaml                                  # or manifest.json
pkg/<package path>/<module path>/module.yaml   # the module manifest
pkg/<package path>/<module path>/<stem>.type.yaml
pkg/<package path>/<module path>/<stem>.value.yaml
deps/<package path>/@/<module path>/…          # one dependency, same shape
```

Every path segment is the escaped spelling of a name, and the extension is the profile's: a tree is
homogeneous, so one profile spells every file in it (document-tree page, "Serialization profile" and
"Directory Structure").

What changed from the layout the CLI wrote before 0.4.0-beta.1:

- **Dependencies live under `deps/`, not `pkg/`.** A dependency's package path ends in a `@` segment, the
  slot a package version would occupy, so one dependency's directory can never be a prefix of another's:
  a package named `a` and a package named `a/b` land at `deps/a/@/` and `deps/a/b/@/` (decision 0015,
  document-tree page, "Dependencies").
- **The distribution manifest records `pathBudget`** — the longest physical path the tree may hold, counted
  from the distribution root, extension included. The CLI writes 4000 unless told otherwise. It is a required
  member, and the reason writing a tree can fail at all (document-tree page, "Write-time truncation and its
  failure"; decision 0012, which keeps `pathBudget` required).
- **A `Library` or `Specs` distribution lists its dependencies by name** in the distribution manifest, with
  each dependency's content in its own `deps/` directory rather than inline.
- **An `Application`'s dependencies are package definitions with a home in the tree**, written under `deps/`
  like any other dependency (MCK document-tree-0009). The older transport had nowhere to put them and refused
  such a distribution; it no longer does. The refusal remains for a dependency whose kind does not match the
  distribution's.
- **`doc` and `access` stay inside each `def`/`spec` file**, not hoisted into the module manifest
  (document-tree page, "access (module manifest)" and "doc").
- **File stems are escaped the way the reference binding escapes them**, and a stem the path budget had to
  truncate is recorded in the module manifest's `fileNames`, which is present only when something was cut
  (decision 0012, which defines the stem grammar, its truncation suffix and `fileNames`).
- **A module specification carrying `annotations` is still refused** — a tree has nowhere to put them — now
  as `morphir::ir::document_tree::invalid_distribution_shape`.

#### Older trees are refused, and how to rewrite one

`pathBudget` is the one required manifest member no older tree carries, so its absence is the reliable signal
that a tree predates the change rather than being merely malformed. Reading such a tree fails with:

```text
morphir::ir::document_tree::missing_member: missing member pathBudget (at manifest#/)
```

carrying the guidance `this tree predates 0.4.0-beta.1; regenerate it with morphir migrate`.

There is no in-place upgrade, because the old tree can no longer be read: write the distribution to a single
file with the CLI that produced the tree, then lay that file out again with 0.4.0-beta.1 or later.

```bash
# with the CLI that wrote the tree (0.4.0-alpha.7 or earlier)
morphir migrate <old-tree> -o model.json --output-layout single-file

# with 0.4.0-beta.1 or later
morphir migrate model.json -o <new-tree> --output-layout vfs
```

Recompiling the source is equally good, and is the better answer when the source is still to hand.

#### Reading a tree: `.yml`, and links

A manifest spelled `manifest.yml` is read as a YAML tree, alongside `manifest.yaml`. It is never written back
as `.yml`: the canonical extension is `.yaml`, and `.yml` is an input spelling only. A logical path that both
a `.yaml` and a `.yml` physical file map to is refused as
`morphir::ir::document_tree::invalid_distribution_shape`, naming both physical spellings.

A document tree is read through real files. The transport never follows a symlink or junction, whether it is
walking the tree or pruning one before a rewrite, so neither reading nor writing can reach outside the tree
root. A manifest that is itself a link is found but not read, and that case has its own diagnostic rather than
the misleading "no manifest" one:

```text
morphir::ir::detection::linked_manifest
```

#### Renamed diagnostics

The document-tree transport no longer carries diagnostic codes of its own for faults the kit already names.
Tooling or tests that matched these by string must be updated; the old codes are pre-release and have no
aliases.

| Old code | Now reported as | Raised when |
| -------- | --------------- | ----------- |
| `morphir::ir::document_tree::name_mismatch` | `morphir::ir::document_tree::invalid_distribution_shape` | A definition file's own `name` is not the name the module manifest listed it under |
| `morphir::ir::document_tree::module_path_mismatch` | `morphir::ir::document_tree::invalid_distribution_shape` | A module manifest's `path` does not match the directory it sits in |

Two refusals are new rather than renamed: `morphir::ir::detection::linked_manifest` above, and
`morphir::ir::document_tree::invalid_path` for a tree nested past 256 directory levels.

This layout and its refusals are decided in decision 0012 (the file-stem definition, its truncation suffix,
`fileNames`, and `pathBudget` staying required) and decision 0015 (the nested dependency directory and its
version segment), and pinned by MCK cases document-tree-0001 to 0009 (finos/morphir-rust#160).

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
def remove_doc_fields(type_or_value):
    """Remove the flattened V4 `doc` member from types/values (decision 0010)."""
    if isinstance(type_or_value, dict) and "doc" in type_or_value:
        return {key: value for key, value in type_or_value.items() if key != "doc"}
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

### YAML output style

Starting in 0.4.0-alpha.7 the CLI writes YAML in the canonical style of the [v4 YAML
profile](v4/yaml-profile.md): a sequence is written in flow style (`[a, b]`) when no
mapping appears anywhere inside it and in block style otherwise, a scalar is quoted only
where the plain spelling would change its meaning (an empty string, a spelling that
resolves to a boolean, null or a number, a leading space or YAML indicator, a trailing
space or colon, an embedded `: ` or ` #`, a control character, or a flow-sequence item
containing `[]{},:#`), members keep the order the encoder writes them in, and the file ends with
exactly one newline. Files written by earlier versions still read: nothing about the
accepted input changed, only the bytes the CLI produces, so a file rewritten by
`morphir migrate` may differ from its predecessor in quoting and line breaks while
carrying the same model.

The same release retires the YAML codec's private diagnostic names for the conformance
kit's:

| Before | Now |
| --- | --- |
| `morphir::ir::yaml::duplicate_key` | `morphir::ir::yaml::duplicate_member` |
| `duplicate_format_version` (duplicate `formatVersion` key, YAML path — the JSON reader still answers `duplicate_format_version`) | `morphir::ir::yaml::duplicate_member` |
| `morphir::ir::yaml::alias_not_allowed` | `morphir::ir::yaml::unsupported_yaml_feature` |
| `morphir::ir::yaml::unsupported_tag` | `morphir::ir::yaml::unsupported_yaml_feature` |
| `morphir::ir::yaml::merge_key_not_allowed` | `morphir::ir::yaml::unsupported_yaml_feature` |
| `morphir::ir::yaml::multiple_documents` | `morphir::ir::yaml::invalid_yaml` |
| `morphir::ir::yaml::non_finite_number` | `morphir::ir::yaml::invalid_literal` |
| `morphir::ir::yaml::budget_exceeded` | `morphir::ir::yaml::nesting_too_deep`, or the parser's `invalid_yaml` |
| `morphir::ir::yaml::invalid_ir` | the specific semantic code for the member at fault |
| `morphir::ir::yaml::ambiguous_scalar` | removed: an unquoted timestamp-like scalar is a string, not an error |

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
