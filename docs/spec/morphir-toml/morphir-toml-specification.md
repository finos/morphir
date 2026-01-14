---
id: morphir-toml-specification
title: "Morphir TOML Configuration Specification"
sidebar_position: 2
description: "Formal specification for morphir.toml configuration files"
---

## Status and scope

This document specifies the **`morphir.toml`** configuration format used by Morphir tooling in this repository.

- **Status**: Draft (versioned and intended to become the authoritative reference)
- **Applies to**: Configuration parsed into `pkg/config.Config`
- **Out of scope**: Morphir IR JSON format (see the IR specification and schemas)

## Files and discovery

Morphir tooling treats a directory as a “workspace” when it contains a `morphir.toml` file (or the hidden variant `.morphir/morphir.toml`).

> This spec focuses on the **file format**, not the multi-source merge rules. For merge precedence and merge behavior, see **[Morphir TOML Configuration Merge Rules](./morphir-toml-merge-rules/)**.

## Data model

`morphir.toml` is a [TOML](https://toml.io/) document. The semantics are defined by its mapping to an equivalent JSON-like object model:

- TOML tables like `[workspace]` map to JSON objects like `{ "workspace": { ... } }`
- Dotted tables like `[toolchain.morphir-elm.tasks.make]` map to nested objects like:
  - `toolchain["morphir-elm"]["tasks"]["make"]`
- Arrays map to JSON arrays
- Inline tables map to JSON objects

## Top-level keys

All top-level keys are optional; absent sections use defaults.

- **`morphir`**: Core Morphir settings (IR version constraints)
- **`workspace`**: Workspace discovery and output layout
- **`project`**: Project metadata (single-project config, or root project in a workspace)
- **`ir`**: IR processing settings
- **`codegen`**: Code generation settings
- **`cache`**: Cache settings
- **`logging`**: Logging settings
- **`ui`**: UI / TUI settings
- **`tasks`**: Project task definitions (intrinsic or command tasks)
- **`workflows`**: Named workflows (staged orchestration of targets)
- **`bindings`**: External binding type-mapping configuration (WIT/Protobuf/JSON)
- **`toolchain`**: Toolchain definitions (external tool adapters and task catalogs)

## Section specifications

### `[morphir]`

- **`version`** (`string`, optional): SemVer constraint indicating compatible Morphir IR versions for the project (example: `"^3.0.0"`). Empty means “any”.

### `[workspace]`

- **`root`** (`string`, optional): Workspace root directory. Empty means “directory containing the config file”.
- **`output_dir`** (`string`, optional, default: `".morphir"`): Output directory for generated artifacts, relative to the workspace root.
- **`members`** (`string[]`, optional): Glob patterns used to discover workspace member projects.
- **`exclude`** (`string[]`, optional): Glob patterns excluded from member discovery.
- **`default_member`** (`string`, optional): Default member path when none is specified.

### `[project]`

- **`name`** (`string`, optional): Project identifier (kebab-case, PascalCase, dotted).
- **`version`** (`string`, optional): Project version.
- **`source_directory`** (`string`, optional): Source directory containing project source files.
- **`exposed_modules`** (`string[]`, optional): Modules exposed by the project’s public API.
- **`module_prefix`** (`string`, optional): Optional module prefix for qualified names.

#### `[project.decorations.<decorationId>]`

Decorations are sidecar metadata schemas/values attached to IR nodes.

- **`display_name`** (`string`, optional): Human-readable name (UI label).
- **`ir`** (`string`, optional): Path to the decoration schema IR file.
- **`entry_point`** (`string`, optional): Fully-qualified type reference of the decoration root type, in the form `Package:Module:Type`.
- **`storage_location`** (`string`, optional): Path to the decoration values file.

### `[ir]`

- **`format_version`** (`int`, optional, default: `3`): IR format version (supported range: 1–10).
- **`strict_mode`** (`bool`, optional, default: `false`): When true, validation warnings are treated as errors.

### `[codegen]`

- **`targets`** (`string[]`, optional): Code generation targets (examples: `"go"`, `"typescript"`, `"scala"`, `"json-schema"`).
- **`template_dir`** (`string`, optional): Custom templates directory.
- **`output_format`** (`string`, optional, default: `"pretty"`): One of `pretty`, `compact`, `minified`.

### `[cache]`

- **`enabled`** (`bool`, optional, default: `true`)
- **`dir`** (`string`, optional): Cache directory path (empty means default).
- **`max_size`** (`int64`, optional, default: `0`): Max cache size in bytes (0 = unlimited).

### `[logging]`

- **`level`** (`string`, optional, default: `"info"`): One of `debug`, `info`, `warn`, `error`.
- **`format`** (`string`, optional, default: `"text"`): One of `text`, `json`.
- **`file`** (`string`, optional): Log file path (empty = stderr).

### `[ui]`

- **`color`** (`bool`, optional, default: `true`)
- **`interactive`** (`bool`, optional, default: `true`)
- **`theme`** (`string`, optional, default: `"default"`): One of `default`, `light`, `dark`.

## Tasks and workflows

### `[tasks.<taskName>]`

Tasks are project-scoped execution units. Each task is either:

- **Intrinsic**: a built-in Morphir action (`kind = "intrinsic"`; `action = "..."`)
- **Command**: an external command (`kind = "command"`; `cmd = ["..."]`)

Common task fields:

- **`depends_on`** (`string[]`, optional)
- **`pre`** (`string[]`, optional)
- **`post`** (`string[]`, optional)
- **`inputs`** (`string[]`, optional)
- **`outputs`** (`string[]`, optional)
- **`params`** (table/object, optional): Arbitrary parameters
- **`env`** (table/object, optional): `string -> string`
- **`mounts`** (table/object, optional): mount name to permission (`"ro"`/`"rw"`)

Intrinsic task fields:

- **`kind`**: `"intrinsic"` (or omitted; omitted defaults to intrinsic)
- **`action`** (`string`, optional): Intrinsic action identifier (example: `morphir.pipeline.compile`)

Command task fields:

- **`kind`**: `"command"`
- **`cmd`** (`string[]`, optional): Command and arguments

### `[workflows.<workflowName>]`

Workflows orchestrate targets in ordered stages.

- **`description`** (`string`, optional)
- **`extends`** (`string`, optional): Base workflow name to inherit from (design/behavior may evolve)
- **`stages`** (`array`, optional): Array of stage objects:
  - **`name`** (`string`, optional)
  - **`targets`** (`string[]`, optional)
  - **`parallel`** (`bool`, optional)
  - **`condition`** (`string`, optional)

## Toolchains

### `[toolchain.<toolchainName>]`

Toolchains define how to acquire and run external tools, and enumerate tasks they provide.

- **`enabled`** (`bool`, optional): If set, explicitly enable/disable the toolchain. If absent, tooling may auto-enable.
- **`version`** (`string`, optional)
- **`working_dir`** (`string`, optional)
- **`timeout`** (`string`, optional): Go-style duration (example: `"5m"`)
- **`env`** (table/object, optional): `string -> string`

#### `[toolchain.<toolchainName>.acquire]`

- **`backend`** (`string`, optional): Acquisition backend (examples: `"path"`; others may be planned)
- **`package`** (`string`, optional): Package identifier (backend-specific)
- **`version`** (`string`, optional): Version constraint (backend-specific)
- **`executable`** (`string`, optional): Executable name/path (backend-specific)

#### `[toolchain.<toolchainName>.tasks.<taskName>]`

- **`exec`** (`string`, optional)
- **`args`** (`string[]`, optional)
- **`fulfills`** (`string[]`, optional): Targets this task fulfills (example: `["make"]`)
- **`variants`** (`string[]`, optional): Supported variants (example: `["Scala", "TypeScript"]`)
- **`env`** (table/object, optional): `string -> string`

##### Inputs

Toolchain task inputs support both forms:

- **Array form**: `inputs = ["src/**/*.elm"]` (treated as file patterns)
- **Table form**:
  - **`files`** (`string[]`, optional)
  - **`artifacts`** (table/object, optional): `string -> string` references (example: `{ ir = "@morphir-elm/make:ir" }`)

##### Outputs

Outputs are a map of named artifacts:

- `[toolchain.<tc>.tasks.<t>.outputs.<outputName>]`
  - **`path`** (`string`, optional)
  - **`type`** (`string`, optional)

## Machine-readable schema

This specification is accompanied by a JSON Schema for the equivalent JSON model:

- `https://morphir.finos.org/schemas/morphir-config-v1.yaml`
- `https://morphir.finos.org/schemas/morphir-config-v1.json`

