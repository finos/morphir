---
title: "Semantic IR Model"
description: "Serialization-neutral Morphir IR version 4 model"
---

# V4 Semantic IR Model

## Status and scope

This page defines the serialization-neutral meaning of Morphir IR version 4. The [JSON profile](json-profile.md), [YAML profile](yaml-profile.md), and [document-tree profile](document-tree-files.md) are physical representations of this model. No one serialization is the semantic model.

The words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY state requirements for conforming implementations.

## Semantic values

A v4 IR artifact denotes one `IRFile` containing a format version and a distribution. A distribution is a Library, Specs, or Application value. Each distribution contains its package identity, dependencies, and either a package definition or specification; an Application also contains entry points.

Packages contain modules. Modules contain documented type and value definitions or specifications. Type expressions, value expressions, patterns, literals, access control, documentation, source locations, incompleteness, and extensions have the meanings defined in the [v4 schema reference](index.md). Their meaning does not depend on JSON object syntax, YAML mapping syntax, whitespace, key order where the model declares a map, quoting, comments, anchors, or file boundaries.

Two serialized artifacts are semantically equal when they normalize to equal versioned Morphir IR values. Serialization conversion is lossless when it preserves this equality. It need not preserve comments, scalar spelling, anchors, aliases, mapping order that is not semantic, or whitespace.

## Names and references

`Name`, `Path`, `PackageName`, `ModuleName`, and `FQName` are semantic name values. Canonical strings and structural word arrays are serialization spellings. A decoder MUST normalize either permitted spelling to the same name value and MUST reject a spelling that has more than one interpretation.

## Logical document identities

A document-tree distribution has logical documents whose identities do not include a physical serialization extension:

- `manifest`
- `pkg/<package>/<module>/module`
- `pkg/<package>/<module>/<name>.type`
- `pkg/<package>/<module>/<name>.value`

The document-tree profile maps these identities to JSON or YAML paths. Tools MUST NOT treat `.json`, `.yaml`, or `.yml` as part of a package, module, type, or value identity.

## Validation order

A conforming reader performs these conceptual stages:

1. Detect the selected serialization profile and layout.
2. Parse physical syntax without lossy coercion.
3. Normalize permitted vocabulary into the versioned semantic model.
4. Validate semantic invariants.
5. Apply requested transformations or version migration.

A diagnostic SHOULD identify its stage and semantic cursor. A syntax diagnostic SHOULD also identify the physical source location.
