---
title: "Schema Version 4"
linkTitle: "Version 4"
weight: 1
description: "Morphir IR JSON Schema for format version 4 (Draft)"
---

# Morphir IR Schema - Version 4 (Draft)

Format version 4 is the next generation of the Morphir IR format. It replaces generic attributes with explicit `TypeAttributes` and `ValueAttributes` structures.

## Overview

Version 4 standardizes attribute handling and adds support for `module.json`.

## Key Changes

- **Explicit Attributes**: `TypeAttributes` and `ValueAttributes` replace the generic `a` parameter.
- **Source Location**: Standardized source location in attributes.
- **Module.json**: Canonical support for independent module files.

## Full Schema

```yaml
# JSON Schema for Morphir IR Format Version 4 (Draft)
$schema: "http://json-schema.org/draft-07/schema#"
$id: "https://morphir.finos.org/schemas/morphir-ir-v4.yaml"
title: "Morphir IR Distribution v4"
type: object
required:
  - formatVersion
  - distribution
properties:
  formatVersion:
    type: integer
    const: 4
  distribution:
    type: array
    items:
      - const: "Library"
      - $ref: "#/definitions/PackageName"
      - $ref: "#/definitions/Dependencies"
      - $ref: "#/definitions/PackageDefinition"

definitions:
  # ... (Definitions similar to v3 but with TypeAttributes/ValueAttributes) ...
  
  # Attributes
  TypeAttributes:
    type: object
    properties:
      source: { $ref: "#/definitions/SourceLocation" }
      constraints: { type: object }
      extensions: { type: object }
  
  ValueAttributes:
    type: object
    properties:
      source: { $ref: "#/definitions/SourceLocation" }
      inferredType: { $ref: "#/definitions/Type" }
      extensions: { type: object }

  SourceLocation:
    type: object
    required: [startLine, startColumn, endLine, endColumn]
    properties:
      startLine: { type: integer }
      startColumn: { type: integer }
      endLine: { type: integer }
      endColumn: { type: integer }

  # ... (Rest of schema) ...
```

See [morphir-ir-v4.yaml](./morphir-ir-v4.yaml) for the file.
