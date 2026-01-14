---
id: morphir-json-specification
title: "Morphir JSON Project Configuration Specification"
sidebar_position: 1
description: "Formal specification for morphir.json (Morphir Elm project configuration)"
---

## Status and scope

This document specifies the **`morphir.json`** project configuration format as used by **`finos/morphir-elm`** and supported for compatibility by Morphir Go tooling.

- **Status**: Draft (versioned and intended to become the authoritative reference)
- **Authoritative source**: `finos/morphir-elm` documentation (see README)
- **Out of scope**: `morphir.toml` (see the `morphir.toml` spec subsection), Morphir IR JSON format (see IR specs/schemas)

## File location

`morphir.json` is located at the **project root directory** and is used by tools such as `morphir-elm make`.

## Data model

`morphir.json` is a JSON object. Keys use **camelCase** (e.g. `sourceDirectory`, `exposedModules`).

## Top-level fields

### `name` (required)

- **Type**: string
- **Meaning**: Package name / module prefix. Should be a valid Elm module name (e.g. `My.Package`).

### `sourceDirectory` (required)

- **Type**: string
- **Meaning**: Directory where the Elm/Morphir source files are located (relative to the project root).

### `exposedModules` (required)

- **Type**: array of strings
- **Meaning**: Modules in the public interface of the package. Module names should exclude the common package prefix.

Example: if `name = "My.Package"` then `exposedModules = ["Foo"]` refers to Elm module `My.Package.Foo`.

### `dependencies` (optional)

- **Type**: array of strings
- **Meaning (morphir-elm)**: URI references to other Morphir IR files.
- **Allowed URI schemes (documented)**: `file://`, `http://`, `https://`, `data://`

### `localDependencies` (optional)

- **Type**: array of strings
- **Meaning (morphir-elm)**: List of **relative paths** to dependency IRs (kept for backwards compatibility).

Example: `"../sibling-folder/morphir-ir.json"`

### `decorations` (optional)

- **Type**: object (map from decoration id → decoration config)
- **Meaning**: Declares sidecar decoration schemas and value locations.

Decoration config object fields:

- **`displayName`** (string, optional): Human-readable name
- **`ir`** (string, optional): Path to the decoration schema IR file
- **`entryPoint`** (string, optional): Fully-qualified type reference `Package:Module:Type`
- **`storageLocation`** (string, optional): Path where decoration values are stored

## Example

```json
{
  "name": "My.Package",
  "sourceDirectory": "src",
  "dependencies": [
    "https://example.com/other/morphir-ir.json"
  ],
  "localDependencies": [
    "../sibling-folder/morphir-ir.json"
  ],
  "exposedModules": [
    "Foo",
    "Bar"
  ],
  "decorations": {
    "myDecoration": {
      "displayName": "My Amazing Decoration",
      "ir": "decorations/my/morphir-ir.json",
      "entryPoint": "My.Amazing.Decoration:Foo:Shape",
      "storageLocation": "my-decoration-values.json"
    }
  }
}
```

## Compatibility notes (Morphir Go)

Morphir Go currently supports `morphir.json` for **basic project metadata** and decorations:

- Implemented: `name`, `sourceDirectory`, `exposedModules`, `decorations`
- Not yet implemented: `dependencies`, `localDependencies`
  - These keys are **ignored** by the current Go parser (unknown JSON fields are ignored during decoding).

## Machine-readable schema

This specification is accompanied by a JSON Schema:

- `https://morphir.finos.org/schemas/morphir-project-v1.yaml`
- `https://morphir.finos.org/schemas/morphir-project-v1.json`

