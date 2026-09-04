---
title: "Schema Architecture"
description: "Architecture of the Morphir IR v4 JSON Schemas"
---

# Schema Architecture

The v4 format is described by two JSON Schema files, both authored as YAML under `website/static/schemas/` and
published as JSON by `website/scripts/yaml-to-json-schemas.js` (`mise run website:build-schemas`).

## Schema Files

```text
website/static/schemas/
├── morphir-ir-v4.yaml                      # Root: single-file distribution (Classic mode)
├── morphir-ir-v4.json                      # Generated from the YAML
├── morphir-ir-v4-document-tree-files.yaml  # Document Tree file kinds
└── morphir-ir-v4-document-tree-files.json  # Generated from the YAML
```

An earlier draft of this page described a nine-file `schemas/v4/{common,classic,tree}/` hierarchy with shared
`$ref` definitions. That hierarchy was never created. The two files above are the only v4 schemas, and the YAML is
the source of truth: editing the JSON directly is overwritten on the next build.

## Classic Mode

`morphir-ir-v4.yaml` is the root schema for a monolithic single-file distribution. Its root requires `formatVersion`
and `distribution`, where `distribution` is one of `Library`, `Specs`, or `Application` in wrapper-object form. All
core vocabulary lives in its `definitions`: names, types, values, patterns, literals, access control, annotations,
and the specification and definition variants.

## Document Tree Mode

`morphir-ir-v4-document-tree-files.yaml` describes the four file kinds of a document tree, which
[Document Tree File Formats](../ir/schemas/v4/document-tree-files.md) specifies in full:

| Definition | Validates |
| ---------- | --------- |
| `DistributionManifestFile` | `manifest.json` or `manifest.yaml` at the root of a distribution |
| `ModuleManifestFile` | `module.json` or `module.yaml`, in manifest style (names only) or inline style (embedded definitions) |
| `TypeDefinitionFile` | `NAME.type.json` or `NAME.type.yaml` |
| `ValueDefinitionFile` | `NAME.value.json` or `NAME.value.yaml` |

Two limitations are open and tracked under the IR v4 stabilization epic:

- The file is a definitions-only catalog. It has no root composition, so a validator must be pointed at one of the
  four definitions explicitly.
- It does not `$ref` the core schema. It restates the shared vocabulary locally, and `TypeDefinition`,
  `TypeSpecification`, and `ValueDefinition` are permissive stubs. A node file's body is therefore not validated
  by this schema today. Validate bodies against `morphir-ir-v4.yaml` until the two files share one definition.

## Polymorphism in Document Tree Nodes

Type and value node schemas use **mutually exclusive keys** to distinguish between implementations and specifications:

```json
{ "def": { ... } } // Validates against TypeDefinition or ValueDefinition
{ "spec": { ... } } // Validates against TypeSpecification or ValueSpecification
```

This lets tools validate the content of a node based on its intended role (definition vs. specification).
