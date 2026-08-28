---
title: "YAML Serialization Profile"
description: "Normative native YAML storage profile for Morphir IR version 4"
---

# V4 YAML Serialization Profile

## Status and scope

This page defines YAML as a native, lossless storage profile for the [v4 semantic IR model](semantic-model.md). It is not the morphir-elm YAML frontend and is not a generated documentation view. JSON and YAML artifacts have equal semantic standing.

The words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY state requirements for conforming implementations.

## YAML processing profile

A YAML IR artifact MUST:

- use YAML 1.2 and UTF-8;
- contain exactly one document and a mapping at its root;
- use strings for mapping keys wherever the semantic model requires names;
- reject duplicate mapping keys;
- reject application-specific and unsupported semantic tags;
- reject cyclic aliases and bound alias expansion, nesting, event count, and input bytes;
- reject merge keys;
- reject implicit timestamps and implementation-specific scalar coercions;
- reject non-finite numbers and numeric values that cannot be represented by the corresponding IR literal without loss.

An implementation MAY accept safe anchors and aliases within its configured bounds. Anchors and aliases are presentation only. The canonical writer does not emit them and does not preserve them across conversion.

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

- use block mappings and block sequences except for specified compact name components;
- use two-space indentation;
- use the field order defined by the concrete profile;
- emit one trailing newline;
- quote strings when plain-scalar resolution could change their meaning;
- avoid tags, anchors, aliases, merge keys, directives, and document-end markers.

Mapping order is not semantic unless the semantic model explicitly defines order. Implementations compare normalized IR values, not YAML text, when proving losslessness.

## File names

Single-file YAML input accepts `.yaml` and `.yml`. Canonical document trees use `.yaml` only: `manifest.yaml`, `module.yaml`, `*.type.yaml`, and `*.value.yaml`.

## Diagnostics

A rejected document produces a diagnostic with a stable code, syntax or normalization stage, severity, semantic cursor when known, recovery guidance, and line and column when the parser provides them. Partial migration does not permit serialization loss or ambiguous YAML.
