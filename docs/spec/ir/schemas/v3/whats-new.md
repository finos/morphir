---
title: "What's New in Version 3"
linkTitle: "What's New"
weight: 1
description: "Changes and improvements in Morphir IR schema version 3"
---

# What's New in Version 3

Version 3 of the Morphir IR schema introduces consistent capitalization across all tags, providing a uniform and predictable format.

## Version 3.1.0

`3.1.0` is a minor revision of version 3. It adds two things: a `Specs` distribution, and the v3 document tree. A
`3.0.0` document stays valid and keeps its meaning.

### Version rules

A writer emits the lowest version that expresses its content:

| Content | `formatVersion` a writer emits |
| --- | --- |
| Single-file `Library` | `3` (the `3.0.0` release), unchanged |
| Single-file `Specs` | `"3.1.0"` |
| Any file of a v3 JSON or YAML document tree | `"3.1.0"` |

A reader of `3.1.0` accepts, in a single-file document, the integer `3` and the strings `"3.0.0"` and `"3.1.0"`. It
refuses a single-file document of `3.2.0` or any later `3.x` release with `unsupported_format_version_minor`. The
reference support table becomes `[3.0.0,3.2.0),[4.0.0,4.1.0)` (see [Format version](../../format-version.md)). A
reader that stays on `[3.0.0,3.1.0)` still reads every `3.0.0` document. It refuses a single-file `Specs` distribution
with the same diagnostic.

A v3 JSON or YAML tree has a stricter rule: its manifest says `"3.1.0"`, and a reader refuses a manifest of any other
3.x release with `version_mismatch` at `manifest#/formatVersion` (see
[Choosing the version on read](./document-tree-files.md#choosing-the-version-on-read)). The draft Ion tree follows its
own [Ion draft](../../../../design/draft/ir/ion.md#document-tree), where a v3 `library` tree still says `"3.0.0"`.

### The Specs distribution

A `Specs` distribution publishes a package's specification without its definitions. It has the shape of a `Library`,
with a package specification in place of the package definition:

| Element | `Library` | `Specs` |
| --- | --- | --- |
| 1 | `"Library"` | `"Specs"` |
| 2 | Package name | Package name |
| 3 | Dependencies: package name and package specification pairs | The same |
| 4 | Package definition | Package specification |

```json
{
  "formatVersion": "3.1.0",
  "distribution": [
    "Specs",
    [["my"], ["pkg"]],
    [],
    {
      "modules": [
        [[["basics"]], { "types": [[["int"], { "doc": "", "value": ["OpaqueTypeSpecification", []] }]], "values": [], "doc": "Basics." }]
      ]
    }
  ]
}
```

The modules of the fourth element are module specifications, spelled as a dependency's modules are. A reader MUST
refuse a module definition there, such as one wrapped in `{ "access", "value" }`. A reader MUST refuse a `Specs`
distribution that declares a release below `3.1.0` (the integer `3` or any `"3.0.x"`) with `specs_before_3_1`. The
rule is the same in every serialization that carries v3.

Migrating a v3 `Specs` distribution to v4 gives a v4 `Specs` distribution with `"formatVersion": 4`, as migrating a
`Library` does.

### The v3 document tree

A v3 distribution can be stored as a JSON or YAML document tree. The tree uses the v4 tree's layout without change and
holds classic v3 payloads. The draft Ion tree is not part of this revision and follows the Ion draft. [Document Tree File Formats (Version 3)](./document-tree-files.md) specifies it.

## Key Changes from Version 2

### Consistent Capitalization

The primary change in version 3 is the **complete capitalization** of all tags throughout the schema:

#### Value Expression Tags

All value expression tags are now capitalized:

- `"apply"` → `"Apply"`
- `"lambda"` → `"Lambda"`
- `"let_definition"` → `"LetDefinition"`
- `"if_then_else"` → `"IfThenElse"`
- `"pattern_match"` → `"PatternMatch"`
- `"literal"` → `"Literal"`
- `"variable"` → `"Variable"`
- `"reference"` → `"Reference"`
- `"constructor"` → `"Constructor"`
- `"tuple"` → `"Tuple"`
- `"list"` → `"List"`
- `"record"` → `"Record"`
- `"field"` → `"Field"`
- `"field_function"` → `"FieldFunction"`
- `"let_recursion"` → `"LetRecursion"`
- `"destructure"` → `"Destructure"`
- `"update_record"` → `"UpdateRecord"`
- `"unit"` → `"Unit"`

#### Pattern Tags

All pattern tags are now capitalized:

- `"wildcard_pattern"` → `"WildcardPattern"`
- `"as_pattern"` → `"AsPattern"`
- `"tuple_pattern"` → `"TuplePattern"`
- `"constructor_pattern"` → `"ConstructorPattern"`
- `"empty_list_pattern"` → `"EmptyListPattern"`
- `"head_tail_pattern"` → `"HeadTailPattern"`
- `"literal_pattern"` → `"LiteralPattern"`
- `"unit_pattern"` → `"UnitPattern"`

#### Literal Tags

All literal tags are now capitalized:

- `"bool_literal"` → `"BoolLiteral"`
- `"char_literal"` → `"CharLiteral"`
- `"string_literal"` → `"StringLiteral"`
- `"whole_number_literal"` → `"WholeNumberLiteral"`
- `"float_literal"` → `"FloatLiteral"`
- `"decimal_literal"` → `"DecimalLiteral"`

## Benefits

### Consistency

Version 3 provides a single, uniform naming convention across the entire IR structure. This makes the schema:

- **Easier to remember**: One rule applies everywhere
- **More predictable**: All tags follow PascalCase capitalization
- **Cleaner to work with**: No need to remember which tags use underscores or lowercase

### Better Tooling Support

The consistent capitalization improves:

- **Code generation**: Automated tools can rely on uniform naming
- **Serialization/Deserialization**: Simplified mapping to programming language types
- **Validation**: Easier to write validation rules and tests

## Migration from Version 2

Migrating from version 2 to version 3 requires updating all lowercase and underscore-separated tags:

1. **Capitalize all value tags**
2. **Capitalize all pattern tags**
3. **Capitalize all literal tags**
4. **Remove underscores** and use PascalCase

## Recommendation

**Version 3 is the current and recommended format** for all new Morphir IR files. It provides the best balance of consistency, clarity, and tooling support.

## See Also

- [Version 3 Overview](../)
- [Full Schema](./full/)
- [Migration from Version 2](../v2/#migration-from-version-2)
