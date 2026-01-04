---
title: "What's New in Version 3"
linkTitle: "What's New"
weight: 1
description: "Changes and improvements in Morphir IR schema version 3"
---

# What's New in Version 3

Version 3 of the Morphir IR schema introduces consistent capitalization across all tags, providing a uniform and predictable format.

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
