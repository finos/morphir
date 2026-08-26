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

`morphir.yaml` is a supported second serialization of this configuration model. See the [Morphir YAML configuration specification](../morphir-yaml/morphir-yaml-specification/).

## Files and discovery

Morphir tooling treats a directory as a project or workspace when it contains exactly one primary configuration in one of these layouts:

| Layout | TOML | YAML |
| --- | --- | --- |
| Root | `morphir.toml` | `morphir.yaml` |
| Hidden | `.morphir/morphir.toml` | `.morphir/morphir.yaml` |
| Dot-config | `.config/morphir/config.toml` | `.config/morphir/config.yaml` |

The six primary paths are alternatives. A loader MUST reject a directory that contains more than one of them and name every conflicting path. It MUST NOT choose a layout or serialization by precedence.

Global user configuration may use the platform config directory or the `.morphir` directory in the user's home. See the [global user path resolution rules](./morphir-toml-merge-rules/#global-user-path-resolution) for XDG, macOS, Windows, and conflict handling.

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
- **`frontend`**: Frontend parsing settings
- **`sources`**: Remote source settings
- **`dependencies`** and **`dev-dependencies`**: Project dependencies and development-only dependencies
- **`extensions`**: Extension definitions
- **`tasks`**: Project task definitions (intrinsic or command tasks)
- **`workflows`**: Named workflows (staged orchestration of targets)
- **`bindings`**: External binding type-mapping configuration (WIT/Protobuf/JSON)
- **`toolchain`**: Toolchain definitions (external tool adapters and task catalogs)

## Section specifications

### `[morphir]`

- **`version`** (`string`, optional): SemVer constraint indicating compatible Morphir IR versions for the project (example: `"^3.0.0"`). Empty means “any”.
- **`min_cli_version`** (`string`, optional): Minimum Morphir CLI version required to work with this configuration.
- **`dev_mode`** (`bool`, optional, default: `false`): Enables development-mode behavior.

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
- **`description`** (`string`, optional): Short description of the project.
- **`license`** (`string`, optional): SPDX license identifier.
- **`repository`** (`string`, optional): URL of the project's source repository.
- **`authors`** (`string[]`, optional): Project authors.
- **`output_directory`** (`string`, optional, default: `".morphir/out"`): Directory for project-level build output.

#### `[project.decorations.<decorationId>]`

Decorations are sidecar metadata schemas/values attached to IR nodes.

- **`display_name`** (`string`, optional): Human-readable name (UI label).
- **`ir`** (`string`, optional): Path to the decoration schema IR file.
- **`entry_point`** (`string`, optional): Fully-qualified type reference of the decoration root type, in the form `Package:Module:Type`.
- **`storage_location`** (`string`, optional): Path to the decoration values file.

### `[ir]`

- **`format_version`** (`int`, optional, default: `4`): IR format version (supported range: 1–10). Version 4 is where active development happens. Version 3 remains supported; a project stays on it by setting this field explicitly.
- **`strict_mode`** (`bool`, optional, default: `false`): When true, validation warnings are treated as errors.
- **`mode`** (`string`, optional, default: `"vfs"`): One of `classic`, `vfs`.

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

### `[frontend]`

Frontend parsing settings.

- **`language`** (`string`, optional): Source language handled by the frontend parser.
- **`emit_parse_stage`** (`bool`, optional, default: `true`): Emit the parse-stage intermediate output.
- **`emit_parse_stage_fatal`** (`bool`, optional, default: `false`): Treat parse-stage errors as fatal.

### `[sources]`

Remote source settings (`morphir_common::remote::config::RemoteSourceConfig`). Unlike most sections in this document, these fields serialize in **camelCase**, not snake_case.

- **`enabled`** (`bool`, optional, default: `true`): Whether remote sources are enabled.
- **`allow`** (`string[]`, optional): Glob patterns. If non-empty, only URLs matching an entry are allowed.
- **`deny`** (`string[]`, optional): Glob patterns denied even when `allow` matches. Takes precedence over `allow`.
- **`trustedGithubOrgs`** (`string[]`, optional): Trusted GitHub organizations/users.

#### `[sources.cache]`

- **`directory`** (`string`, optional): Cache directory (defaults to a platform cache directory under `morphir/sources`).
- **`maxSizeMb`** (`int`, optional, default: `0`): Maximum cache size in MB (`0` = unlimited).
- **`ttlSecs`** (`int`, optional, default: `0`): TTL for cached sources in seconds (`0` = never expire).

#### `[sources.network]`

- **`timeoutSecs`** (`int`, optional, default: `30`): Connection timeout in seconds.
- **`httpProxy`** (`string`, optional): HTTP proxy URL.
- **`httpsProxy`** (`string`, optional): HTTPS proxy URL.
- **`maxRedirects`** (`int`, optional, default: `10`): Maximum number of redirects to follow.
- **`userAgent`** (`string`, optional): User agent string.

### `[dependencies]` and `[dev-dependencies]`

Maps of dependency name to a version constraint or a detailed table. `dependencies` lists the project's dependencies; `dev-dependencies` lists dependencies needed only for development.

```toml
[dependencies]
acme-sdk = "^1.2.0"
local-lib = { path = "../local-lib" }
upstream = { git = "https://example.com/upstream.git", tag = "v2.0.0" }

[dev-dependencies]
test-utils = { workspace = true }
```

Each entry is either:

- **A version string**: a SemVer constraint.
- **A table**:
  - **`version`** (`string`, optional)
  - **`path`** (`string`, optional)
  - **`git`** (`string`, optional)
  - **`tag`** (`string`, optional)
  - **`branch`** (`string`, optional)
  - **`rev`** (`string`, optional)
  - **`workspace`** (`bool`, optional)

### `[extensions.<name>]`

- **`path`** (`string`, optional)
- **`url`** (`string`, optional)
- **`command`** (`string`, optional)
- **`args`** (`string[]`, optional)
- **`enabled`** (`bool`, optional, default: `true`)
- **`config`** (table, optional): Extension-specific configuration.

## Secret values

Some settings hold credentials. A conforming loader MUST treat a value at a position the schema declares as `secretValue` as secret: it MUST NOT display, log, or serialize the value, and tooling MUST obtain it only through an explicit exposing operation. Schema version 1 defines `secretValue` but does not yet reference it from any property; the rule takes effect as soon as a credential field such as `registry.token` is declared with that type.

A secret can also be supplied as a **secret reference**, which names where to obtain the secret instead of containing it:

```toml
[registry]
token = { env = "GITHUB_TOKEN" }
password = { file = "~/.config/morphir/registry-password" }
command_token = { command = ["gh", "auth", "token"] }
keyring_token = { keyring = { service = "github.com", account = "damre" } }
```

A secret reference has exactly one of these four shapes. A loader MUST recognise these shapes at every position, not only at positions the schema declares as secret.

- `env`: the secret is the value of the named environment variable. A missing or empty variable is an error when the secret is resolved.
- `file`: the secret is the file's UTF-8 contents with one trailing `\n` or `\r\n` removed. A relative path resolves against the directory of the configuration file that declares the reference; a leading `~` expands to the user's home directory. A missing, unreadable, non-UTF-8, or empty file is an error when the secret is resolved.
- `command`: the non-empty string array names a program followed by its arguments. Morphir executes that program directly, without a shell, with standard input closed. It runs in the declaring configuration file's directory, or in the process current directory when the reference has no declaring file. The program must succeed and write non-empty UTF-8 text to standard output after one trailing `\n` or `\r\n` is removed.
- `keyring`: the mapping has exactly the non-empty string fields `service` and `account`. Morphir reads the matching password from the native operating-system keyring. It does not create, update, or delete keyring entries. A missing, unreadable, or empty entry is an error when the secret is resolved.

Any other table, including one with mixed discriminator keys, extra keys, an empty command, or an incomplete keyring mapping, is not a secret reference.

Resolution happens only when tooling explicitly requests one dotted configuration key. It resolves that one winning leaf and MUST NOT traverse or resolve other references. The resolved value is protected: formatting and serialization redact it, and callers need an explicit exposure operation to read it. Resolution failures identify the requested key, reference kind, or safe source metadata, but MUST NOT disclose resolved secret text.

Displaying the configuration, reporting sources, validating, decoding, and normal loading MUST NOT resolve references. A reference MAY be displayed verbatim because it contains no secret; a plain-string secret MUST be displayed as a placeholder such as `<redacted>`.

For merging, a secret reference is a leaf: a higher-precedence reference replaces a lower one entirely (see the [merge rules](./morphir-toml-merge-rules/)).

The shared schema defines the four reference shapes. Implementations built on morphir-rust require Rust 1.88 or later.

## Tasks and workflows

### `[tasks.<taskName>]`

Tasks are project-scoped execution units. Each task is either:

- **Intrinsic**: a built-in Morphir action (`kind = "intrinsic"`; `action = "..."`)
- **Command**: an external command (`kind = "command"`; `cmd = ["..."]`)

A string value is shorthand for a command task run through the shell: `build = "cargo build"`.

`depends` and `run` relate to the pre-existing `depends_on` and `cmd`/`action` fields as follows:

- **`depends`** is an accepted alternative spelling of **`depends_on`**. A task MUST NOT set both `depends_on` and `depends`.
- **`run`** is the string form of a command task: it is equivalent to the string shorthand above, and its presence implies `kind = "command"`. A task MUST NOT set both `run` and `cmd`, and MUST NOT set both `run` and `action`.

> The schema enforces the two MUST-NOT rules above (a task cannot declare both members of either pair). It does not separately enforce that `run` implies `kind = "command"` when `kind` is omitted, because doing so would require restructuring the intrinsic/command task variants in the schema. A conforming loader MUST still apply the implication: a task with `run` set and `kind` omitted (and no conflicting `action`) is a command task, not an intrinsic one.

Common task fields:

- **`depends_on`** (`string[]`, optional)
- **`depends`** (`string[]`, optional): Alternative spelling of `depends_on` (see above).
- **`pre`** (`string[]`, optional)
- **`post`** (`string[]`, optional)
- **`inputs`** (`string[]`, optional)
- **`outputs`** (`string[]`, optional)
- **`params`** (table/object, optional): Arbitrary parameters
- **`env`** (table/object, optional): `string -> string`
- **`mounts`** (table/object, optional): mount name to permission (`"ro"`/`"rw"`)
- **`description`** (`string`, optional)
- **`run`** (`string`, optional): Shell command to run (alternative to `cmd`; see above).
- **`cwd`** (`string`, optional)

Intrinsic task fields:

- **`kind`**: `"intrinsic"` (or omitted; omitted defaults to intrinsic, unless `run` is present without `action`, in which case the task is a command task per the rule above)
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
