---
id: morphir-yaml-specification
title: "Morphir YAML configuration specification"
sidebar_position: 1
description: "Proposed specification for morphir.yaml configuration files"
---

## Status and scope

This document specifies the proposed `morphir.yaml` configuration format. It is a second serialization of the same configuration model as `morphir.toml`.

- Status: Draft design. Repository tooling does not yet claim support for loading `morphir.yaml`.
- Applies to: Project, workspace, user, and system configuration.
- Out of scope: Morphir IR YAML and the legacy `morphir.json` project file.

The words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY state requirements for conforming implementations.

## Design rule

Parsing equivalent TOML and YAML files MUST produce the same nested configuration value. Field names, defaults, validation, path resolution, and merge behavior do not change with the serialization.

For example, these documents are equivalent:

```toml title="morphir.toml"
[project]
name = "acme/orders"
source_directory = "src"
exposed_modules = ["Orders.Api", "Orders.Types"]

[ir]
format_version = 3
strict_mode = true
```

```yaml title="morphir.yaml"
project:
  name: acme/orders
  source_directory: src
  exposed_modules:
    - Orders.Api
    - Orders.Types

ir:
  format_version: 3
  strict_mode: true
```

Both parse to:

```json
{
  "project": {
    "name": "acme/orders",
    "source_directory": "src",
    "exposed_modules": ["Orders.Api", "Orders.Types"]
  },
  "ir": {
    "format_version": 3,
    "strict_mode": true
  }
}
```

## YAML profile

A `morphir.yaml` file MUST meet these syntax rules:

- Use YAML 1.2 and the Core Schema.
- Encode the file as UTF-8.
- Contain exactly one YAML document.
- Use a mapping at the document root.
- Use strings for every mapping key. Keys are case-sensitive.
- Use only values that have a direct TOML and JSON representation: mappings, sequences, strings, finite numbers, and booleans.
- Reject null values. Omit an optional key instead.
- Reject duplicate mapping keys.
- Reject custom tags, anchors, aliases, and the YAML merge key `<<`.

These limits remove features that YAML libraries handle differently. They also make conversion to the shared JSON-equivalent configuration model deterministic.

Authors SHOULD quote a string when a reader could mistake it for another scalar type. This is especially useful for versions, durations, dates, and strings such as `null`, `true`, or `1.0`.

```yaml
project:
  version: "1.0"

toolchain:
  morphir-elm:
    timeout: "5m"
```

## Configuration model

The root mapping accepts the same optional keys as `morphir.toml`:

| Key | Value | Meaning |
| --- | --- | --- |
| `morphir` | mapping | Morphir IR version constraints |
| `workspace` | mapping | Workspace discovery and output layout |
| `project` | mapping | Project metadata and decorations |
| `ir` | mapping | IR processing settings |
| `codegen` | mapping | Code generation settings |
| `cache` | mapping | Cache settings |
| `logging` | mapping | Logging settings |
| `ui` | mapping | UI and TUI settings |
| `tasks` | mapping | Project task definitions |
| `workflows` | mapping | Named workflows |
| `bindings` | mapping | External binding type mappings |
| `toolchain` | mapping | External tool adapters and task catalogs |

The field definitions, allowed values, defaults, and constraints in the [Morphir TOML configuration specification](../morphir-toml/morphir-toml-specification/) are normative for both serializations. In YAML, each TOML table becomes a mapping and each TOML array becomes a sequence. Snake-case field names remain unchanged.

The machine-readable definition is the shared [Morphir configuration schema](/schemas/morphir-config-v1.yaml). A loader MUST validate the parsed configuration value, not the YAML syntax tree, against that schema.

Unknown properties follow the shared schema. Version 1 currently permits them so tools can add settings without invalidating the whole document. A tool MAY warn when it does not recognize a property, but it MUST preserve the distinction between an unknown property and a known property with an invalid value.

## File names and discovery

`morphir.yaml` is the canonical YAML file name. A conforming implementation MUST NOT discover `morphir.yml` implicitly. A user may still select a `.yml` file through a command option that accepts an explicit path.

YAML uses the locations corresponding to the TOML configuration sources:

| Precedence | YAML path |
| --- | --- |
| System | `/etc/morphir/morphir.yaml` |
| Global user | `~/.config/morphir/morphir.yaml` |
| Project | `morphir.yaml` or `.morphir/morphir.yaml` |
| User override | `.morphir/morphir.user.yaml` |

Built-in defaults and `MORPHIR_*` environment variables have no file serialization.

At one location, a loader MUST accept at most one serialization. If corresponding TOML and YAML files both exist, discovery MUST fail with an ambiguity error that names both files. A loader MUST NOT merge sibling TOML and YAML files or choose one by extension precedence.

The hidden and non-hidden project paths are alternate locations, not two merge layers. If both exist, discovery MUST report the same kind of ambiguity.

## Merge behavior

After parsing, YAML sources use the [Morphir configuration merge rules](../morphir-toml/morphir-toml-merge-rules/). The merge algorithm operates on the configuration model, so maps merge recursively, sequences replace earlier sequences, and later sources take precedence.

## Complete example

```yaml title="morphir.yaml"
morphir:
  version: "^3.0.0"

workspace:
  output_dir: .morphir
  members:
    - packages/*
  exclude:
    - packages/experimental-*
  default_member: packages/orders

project:
  name: acme/orders
  version: "1.2.0"
  source_directory: src
  exposed_modules:
    - Orders.Api
  module_prefix: Orders
  decorations:
    pii:
      display_name: Personal data
      ir: decorations/pii-ir.json
      entry_point: Acme.Decorations:Pii:Definition
      storage_location: decorations/pii-values.json

ir:
  format_version: 3
  strict_mode: true

codegen:
  targets:
    - go
    - json-schema
  template_dir: templates
  output_format: pretty

cache:
  enabled: true
  dir: .morphir/cache
  max_size: 1073741824

logging:
  level: info
  format: text

ui:
  color: true
  interactive: true
  theme: default

tasks:
  compile:
    kind: intrinsic
    action: morphir.pipeline.compile
    inputs:
      - src/**/*.elm
    outputs:
      - .morphir/morphir-ir.json
    params:
      optimize: true
  check-generated:
    kind: command
    cmd:
      - git
      - diff
      - --exit-code
      - generated
    depends_on:
      - compile
    env:
      CI: "true"

workflows:
  verify:
    description: Compile the model and check generated files
    stages:
      - name: build
        targets:
          - compile
      - name: check
        targets:
          - check-generated
        parallel: false

bindings:
  wit:
    primitives:
      - external: u64
        morphir: Morphir.SDK:Int:Int
        bidirectional: true
        priority: 100

toolchain:
  morphir-elm:
    enabled: true
    version: "2.90.0"
    working_dir: .
    timeout: "5m"
    acquire:
      backend: path
      executable: morphir-elm
    tasks:
      make:
        exec: morphir-elm
        args:
          - make
        fulfills:
          - make
        inputs:
          files:
            - src/**/*.elm
        outputs:
          ir:
            path: .morphir/morphir-ir.json
            type: morphir-ir
```

## Conversion requirements

A TOML-to-YAML converter MUST preserve the parsed configuration value. Comments, key order, quoting style, and whitespace are presentation details and do not need to survive conversion.

A converter MUST report a value that the target serialization cannot represent without loss. It MUST NOT coerce that value silently. Every field defined by the shared configuration schema has a direct representation in both formats.

## Implementation checklist

A Morphir tool that adds YAML support should:

1. Discover `morphir.yaml` at the supported source locations.
2. Detect sibling-file and alternate-project-path ambiguity before loading configuration.
3. Parse the restricted YAML 1.2 profile into the shared configuration model.
4. Validate that value with `morphir-config-v1`.
5. Apply the serialization-independent merge rules.
6. Include the source path and YAML location in parse and validation diagnostics.
