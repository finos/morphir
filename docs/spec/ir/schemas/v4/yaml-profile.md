---
title: "YAML Serialization Profile"
description: "Normative native YAML storage profile for Morphir IR version 4"
---

# V4 YAML Serialization Profile

## Status and scope

This page defines YAML as a native, lossless storage profile for the [v4 semantic IR model](semantic-model.md). It is not the morphir-elm YAML frontend and is not a generated documentation view. JSON and YAML artifacts have equal semantic standing.

Version 4 inherits the shared [`formatVersion` contract](../../format-version.md). Integer `4` aliases exactly `4.0.0`; the exact baseline string `"4.0.0"` is valid input; and later v4 revisions use strict release strings such as `"4.0.1"`. Canonical writers emit integer `4` for the baseline and an exact string for a nonzero minor or patch revision.

The words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY state requirements for conforming implementations.

## YAML processing profile

A YAML IR artifact MUST:

- use YAML 1.2 and UTF-8;
- contain exactly one document and a mapping at its root;
- use strings for mapping keys wherever the semantic model requires names;
- reject duplicate mapping keys;
- reject every explicit YAML tag, whether application-specific or a `!!` core-schema tag ([Reader restrictions](#reader-restrictions));
- reject every anchor and alias, and reject merge keys;
- bound nesting depth, event count, and input bytes while parsing, independent of that rejection;
- reject implicit timestamps and implementation-specific scalar coercions;
- reject non-finite numbers and numeric values that cannot be represented by the corresponding IR literal without loss.

Anchors and aliases are presentation only: a reader rejects them (`unsupported_yaml_feature`), and the canonical writer never emits them.

## Explicit structural vocabulary

Every valid concrete v4 node has an explicit YAML representation. The explicit representation is the v4 JSON data model written with YAML mappings, sequences, strings, booleans, nulls where the semantic model permits them, and finite numbers. JSON object member names become YAML string keys; JSON arrays become YAML sequences. Externally tagged variants use a one-entry mapping, not a YAML semantic tag.

For example, an explicit package name may use its structural words:

```yaml
packageName:
  - [example]
```

The explicit representation is the fallback for every node without a specified shorthand. A writer MUST NOT omit, coerce, or reinterpret a node merely to make YAML shorter.

## Readable vocabulary

The preferred vocabulary uses canonical string spellings where v4 defines a one-to-one normalization. For example:

```yaml
packageName: example
```

Canonical `Name`, `Path`, `PackageName`, `ModuleName`, `FQName`, simple type reference, and parameterized type reference spellings normalize according to the v4 naming and type rules. A readable spelling MUST have exactly one expansion to the explicit structural vocabulary. A reader MUST reject ambiguous shorthand rather than guess.

The canonical YAML writer emits readable vocabulary where this specification defines it and the explicit structural vocabulary otherwise. Vocabulary selection is independent of IR version, serialization format, storage layout, normalization policy, and publication target.

## Deterministic output

Canonical YAML output MUST:

- use block style for mappings and use block style for sequences unless the [Canonical writer](#canonical-writer)
  section makes them flow (a sequence holding no mapping at any depth, or an empty mapping or sequence, which are
  written inline as `{}` and `[]`);
- use two-space indentation;
- use the field order defined by the concrete profile;
- emit one trailing newline;
- quote strings when plain-scalar resolution could change their meaning;
- avoid tags, anchors, aliases, merge keys, directives, and document-end markers.

Mapping order is not semantic unless the semantic model explicitly defines order. Implementations compare normalized IR values, not YAML text, when proving losslessness.

Readers MUST accept `formatVersion` before or after `distribution`. Canonical YAML output MUST place `formatVersion` first and `distribution` second. A linter SHOULD report `format_version_not_first` when another root member appears first, but this warning MUST NOT cause rejection.

## Canonical writer

The rules below fix the bytes a canonical v4 YAML writer emits, so that every binding and every mirror emits
the same file for the same IR value. The [Morphir Compatibility Kit](https://github.com/finos/morphir/tree/main/spec/ir/mck)
is the authority: its `yaml canonical` fences are the reference, and where a rule below and a fence disagree,
the fence wins and this page is corrected.

1. **Root.** A scalar root is written as the scalar followed by a newline. A mapping root is a block mapping.
   A sequence root follows rule 3.
2. **Mappings** MUST be block style with two-space indentation, and MUST keep members in the order the v4 writer
   produced them. Each member is `key:` followed by a space and an inline scalar, or by a newline and an
   indented block for a nested mapping or a block sequence. An empty mapping MUST be written inline as `{}`.
   Keys are written as scalars under rule 4.
3. **Sequences** MUST be flow style — `[a, b]`, one space after each comma, no trailing comma — when the
   sequence contains no mapping at any depth. Nested scalar-only sequences therefore stay inline:
   `just: [[value, a]]`. A sequence MUST be block style (`- ` items) as soon as any item, at any depth, is a
   mapping; inside a block sequence a mapping item starts on its `- ` line. An empty sequence MUST be written
   inline as `[]`.
4. **Strings** MUST be plain unless plain resolution would change their meaning or they contain YAML syntax, in
   which case they MUST be double-quoted with JSON escapes. Plain is refused when the string:
   - is empty;
   - resolves under [Scalar resolution](#scalar-resolution) to a non-string
     (`true`, `True`, `TRUE`, `false`, `False`, `FALSE`, `null`, `Null`, `NULL`, `~`, `42`, `1e3`, `0x1F`, `.inf`, `.nan`, …);
   - starts with one of `- ? : , [ ] { } # & * ! | > ' " % @ \`` or with a space;
   - ends with a space or with `:`;
   - contains `: `, ` #`, a newline, a tab, or any control character;
   - or, **inside a flow sequence only**, contains any of `[ ] { } , : #`.

   An FQName-like string is therefore plain in every position except a flow sequence: `morphir/SDK:basics#int`
   as a mapping value is plain, while `"morphir/SDK:list#list"` inside a flow sequence is quoted. A key such as
   `$meta` is plain.
5. **Numbers** MUST be written from their lexeme, unchanged. Booleans and null MUST be written `true`, `false`,
   and `null`.
6. **Output** MUST end with exactly one newline and MUST contain no tags, anchors, aliases, comments,
   directives, or document markers.

Block scalars (`|`, `>`) are never emitted; a multi-line string is double-quoted with `\n` escapes.

## Reader restrictions

A conforming YAML reader produces the same value tree the JSON reader produces for the equivalent document:
ordered mapping members and lexeme-preserving numbers. Each row below is a rejection with a stable diagnostic
code, stage `syntax`, a semantic cursor (`/` at the root, the JSON pointer of the offending node otherwise), and
line and column when the parser provides them.

| Input | Outcome |
| --- | --- |
| Zero documents, or more than one (`---` twice; `...` then content) | `invalid_yaml`: "expected exactly one document" |
| A parser error | `invalid_yaml` with the parser's message and position |
| A duplicate mapping key | `duplicate_member` at the key (the same code the JSON profile uses, with the same meaning) |
| An anchor or an alias anywhere | `unsupported_yaml_feature`: "anchors and aliases are not part of the profile" |
| An explicit tag (`!!int`, `!!map`, `!foo`, …) | `unsupported_yaml_feature`: "tags are not part of the profile" |
| A `<<` merge key | `unsupported_yaml_feature`: "merge keys are not part of the profile" |
| A directive (`%YAML`, `%TAG`) | `unsupported_yaml_feature` |
| A non-string mapping key (number, boolean, null, mapping, sequence) | `invalid_type`: "mapping keys must be strings" |
| A non-finite number (`.inf`, `-.inf`, `.nan`) | `invalid_literal`: "non-finite numbers are not part of the profile" |

### Scalar resolution

Resolution applies to plain scalars only. Every quoted scalar and every block scalar is a string.

- `true`, `True`, and `TRUE` resolve to the boolean `true`; `false`, `False`, and `FALSE` resolve to the boolean
  `false`; `null`, `Null`, `NULL`, `~`, and the empty scalar resolve to null.
- Numbers are resolved in two steps that a reader applies in this order, so the integer form is tried first and
  the float form only applies to text the integer form did not match:
  1. A YAML 1.2 core decimal integer (`[-+]?[0-9]+`) resolves to a number whose lexeme is the source text
     with any leading `+` removed: `+1` becomes `1`, `-7` stays `-7`.
  2. Otherwise, a YAML 1.2 core float (`[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?`) resolves to a
     number with the source lexeme, except that a lexeme JSON would not accept is rewritten to the shortest
     JSON form denoting the same value: `.5` becomes `0.5`, `5.` becomes `5.0`, `+1.5` becomes `1.5`,
     `+.5e3` becomes `0.5e3`. A lexeme JSON already accepts (`1.5E3`) is kept as written.
  In both steps the rewrite is a normalization, not a warning, and it never changes the value. A leading zero
  (`01`, `-007`, and the same in a float such as `01.5`) is rejected with `invalid_literal` ("leading zeros are
  not part of the profile") before either rewrite, because it is not a JSON lexeme. Octal (`0o17`) and
  hexadecimal (`0xF`) integers are **rejected** with `invalid_literal` ("write decimal"): the IR carries a
  lexeme, and these forms have no JSON lexeme to carry.
- Everything else is a string, **including date-looking text** such as `2026-01-15`. YAML 1.2 core has no
  implicit timestamps, and this profile forbids implicit coercions, so a plain `2026-01-15` where a literal is
  expected is a `StringLiteral`, never a date.

Block scalars are accepted on input and produce their folded or literal string; see rule 6 for why a writer
never emits one.

## File names

Single-file YAML input accepts `.yaml` and `.yml`. Canonical document trees use `.yaml` only: `manifest.yaml`, `module.yaml`, `*.type.yaml`, and `*.value.yaml`.

## Diagnostics

A rejected document produces a diagnostic with a stable code, syntax or normalization stage, severity, semantic cursor when known, recovery guidance, and line and column when the parser provides them. Partial migration does not permit serialization loss or ambiguous YAML.
