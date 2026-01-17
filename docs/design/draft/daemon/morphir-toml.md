---
title: morphir.toml Specification
sidebar_label: morphir.toml
sidebar_position: 9
status: draft
---

# morphir.toml Specification

This document provides the complete specification for the `morphir.toml` configuration file format.

## File Format

Morphir uses [TOML v1.0.0](https://toml.io/en/v1.0.0) for configuration files. All configuration is in `morphir.toml` at the project or workspace root.

## Top-Level Sections

| Section | Required | Description |
|---------|----------|-------------|
| `[morphir]` | No | Morphir toolchain settings |
| `[project]` | Conditional | Project metadata (required for project mode) |
| `[workspace]` | Conditional | Workspace settings (required for workspace mode) |
| `[frontend]` | No | Source language configuration |
| `[ir]` | No | IR format and generation settings |
| `[codegen]` | No | Code generation targets and options |
| `[dependencies]` | No | Project dependencies |
| `[dev-dependencies]` | No | Development-only dependencies |
| `[extensions]` | No | Extension registration |
| `[tasks]` | No | Custom tasks and hooks |
| `[test]` | No | Test configuration |
| `[publish]` | No | Publishing configuration |

## `[morphir]` Section

Morphir toolchain version and global settings.

```toml
[morphir]
# Required Morphir IR version (semver constraint)
# Ensures compatibility with toolchain and extensions
version = "^4.0.0"

# Minimum CLI version required (optional)
min_cli_version = "4.0.0"
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `version` | string | Required | Semver constraint for IR version (e.g., `"^4.0.0"`, `"~4.1"`, `"4.0.0"`) |
| `min_cli_version` | string | None | Minimum CLI version required |

### Version Constraint Syntax

| Syntax | Meaning | Example |
|--------|---------|---------|
| `"4.0.0"` | Exact version | Only 4.0.0 |
| `"^4.0.0"` | Compatible (major) | >=4.0.0 <5.0.0 |
| `"~4.1.0"` | Compatible (minor) | >=4.1.0 <4.2.0 |
| `">=4.0.0"` | Minimum version | 4.0.0 or higher |
| `">=4.0.0, <5.0.0"` | Range | Between 4.0.0 and 5.0.0 |

## `[project]` Section

Project metadata and structure. Required for project mode.

```toml
[project]
# Package identifier (organization/name format)
name = "my-org/my-project"

# Semantic version
version = "1.0.0"

# Human-readable description
description = "A Morphir domain model for order processing"

# Package authors
authors = ["Jane Doe <jane@example.com>"]

# License identifier (SPDX)
license = "Apache-2.0"

# Repository URL
repository = "https://github.com/my-org/my-project"

# Homepage URL
homepage = "https://my-org.github.io/my-project"

# Source directory (relative to morphir.toml)
source_directory = "src"

# Modules exposed as public API
exposed_modules = ["Domain.User", "Domain.Order", "Domain.Product"]

# Output directory for build artifacts
output_directory = ".morphir-dist"

# Keywords for package discovery
keywords = ["domain", "orders", "e-commerce"]
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | Required | Package identifier in `org/name` format |
| `version` | string | Required | Semantic version (e.g., `"1.0.0"`, `"2.1.0-beta.1"`) |
| `description` | string | `""` | Human-readable description |
| `authors` | array | `[]` | List of authors (name and/or email) |
| `license` | string | None | SPDX license identifier |
| `repository` | string | None | Repository URL |
| `homepage` | string | None | Homepage URL |
| `source_directory` | string | `"src"` | Source code directory |
| `exposed_modules` | array | All modules | Modules in the public API |
| `output_directory` | string | `".morphir-dist"` | Build output directory |
| `keywords` | array | `[]` | Keywords for discovery |

### Package Name Format

Package names follow the format `organization/project-name`:

- **Organization**: Lowercase, alphanumeric, hyphens allowed (e.g., `my-org`, `finos`)
- **Project**: Lowercase, alphanumeric, hyphens allowed (e.g., `my-project`, `morphir-sdk`)
- **Separator**: Forward slash `/`

Examples:
- `morphir/sdk`
- `my-company/order-domain`
- `finos/morphir-examples`

## `[workspace]` Section

Workspace configuration for multi-project setups.

```toml
[workspace]
# Glob patterns for discovering member projects
members = [
    "packages/*",
    "libs/*",
    "apps/*"
]

# Patterns to exclude from member discovery
exclude = [
    "packages/deprecated-*",
    "packages/internal-*"
]

# Default member for commands without --project flag
default_member = "packages/core"

# Shared output directory
output_dir = ".morphir"

# Parallel build settings
parallel = true
max_jobs = 4
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `members` | array | `[]` | Glob patterns for member discovery |
| `exclude` | array | `[]` | Patterns to exclude from discovery |
| `default_member` | string | None | Default project for commands |
| `output_dir` | string | `".morphir"` | Workspace output directory |
| `parallel` | bool | `true` | Enable parallel builds |
| `max_jobs` | integer | CPU count | Maximum parallel jobs |

### Member Discovery

Members are discovered by:
1. Matching directories against `members` patterns
2. Excluding matches against `exclude` patterns
3. Finding `morphir.toml` with `[project]` section in matched directories

## `[frontend]` Section

Source language and parser configuration.

```toml
[frontend]
# Default source language
language = "elm"

# Language-specific settings
[frontend.elm]
elm_version = "0.19"
optimize = true

[frontend.morphir-dsl]
strict_mode = true
allow_incomplete = false

# Pattern-based language selection
[[frontend.rules]]
pattern = "src/legacy/**/*.morphir"
language = "morphir-dsl"

[[frontend.rules]]
pattern = "src/experimental/**/*.ml"
language = "ocaml"
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `language` | string | Auto-detect | Default source language |

### Built-in Languages

| Language | Extensions | Description |
|----------|------------|-------------|
| `elm` | `.elm` | Elm source files |
| `morphir-dsl` | `.morphir`, `.mdsl` | Morphir DSL |

### Language-Specific Options

#### `[frontend.elm]`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `elm_version` | string | `"0.19"` | Elm language version |
| `optimize` | bool | `false` | Enable optimizations |

#### `[frontend.morphir-dsl]`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `strict_mode` | bool | `false` | Strict parsing mode |
| `allow_incomplete` | bool | `true` | Allow incomplete definitions |

### Frontend Rules

Rules select language based on file path patterns:

```toml
[[frontend.rules]]
pattern = "src/**/*.elm"      # Glob pattern
language = "elm"              # Language for matching files
```

Rules are evaluated in order; first match wins.

## `[ir]` Section

IR format and generation settings.

```toml
[ir]
# IR format version
format_version = 4

# Output mode
mode = "vfs"  # "classic" or "vfs"

# Strict mode (fail on warnings)
strict_mode = false

# Include source locations in IR
include_source_locations = true

# Preserve documentation
include_docs = true
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `format_version` | integer | `4` | IR format version |
| `mode` | string | `"vfs"` | Output mode: `"classic"` (single file) or `"vfs"` (directory tree) |
| `strict_mode` | bool | `false` | Treat warnings as errors |
| `include_source_locations` | bool | `true` | Include source locations in IR |
| `include_docs` | bool | `true` | Include documentation in IR |

## `[codegen]` Section

Code generation configuration.

```toml
[codegen]
# Targets to generate
targets = ["typescript", "scala", "spark"]

# Output format
output_format = "pretty"  # "pretty" or "compact"

# Output directory (relative to project output)
output_dir = "generated"

# Target-specific configuration
[codegen.typescript]
module_format = "esm"
strict = true

[codegen.scala]
package_prefix = "com.myorg"
scala_version = "2.13"

[codegen.spark]
spark_version = "3.5"
scala_version = "2.13"

# Module-specific target overrides
[codegen.modules."Domain.Api"]
targets = ["typescript"]  # Only generate TypeScript for this module

[codegen.modules."Domain.Internal"]
targets = []  # Skip codegen for internal modules

# Pattern-based rules
[[codegen.rules]]
pattern = "**/Internal/**"
targets = []

[[codegen.rules]]
pattern = "**/Api/**"
targets = ["typescript", "openapi"]
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `targets` | array | `[]` | Code generation targets |
| `output_format` | string | `"pretty"` | Output formatting |
| `output_dir` | string | `"generated"` | Output directory |

### Built-in Targets

| Target | Description |
|--------|-------------|
| `typescript` | TypeScript/JavaScript |
| `scala` | Scala 2.x/3.x |
| `java` | Java |
| `spark` | Apache Spark |
| `json-schema` | JSON Schema |
| `openapi` | OpenAPI specification |

### Target-Specific Options

#### `[codegen.typescript]`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `module_format` | string | `"esm"` | `"esm"`, `"commonjs"`, or `"umd"` |
| `strict` | bool | `true` | Enable strict TypeScript |
| `declaration` | bool | `true` | Generate `.d.ts` files |

#### `[codegen.scala]`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `package_prefix` | string | None | Package prefix |
| `scala_version` | string | `"2.13"` | Scala version |

#### `[codegen.spark]`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `spark_version` | string | `"3.5"` | Spark version |
| `scala_version` | string | `"2.13"` | Scala version |

## `[dependencies]` Section

Project dependencies.

```toml
[dependencies]
# Path dependency (local)
"my-org/common" = { path = "../common" }

# Version dependency (from registry)
"morphir/sdk" = "^3.0.0"

# Git dependency
"other-org/utils" = { git = "https://github.com/other-org/utils.git", tag = "v1.0.0" }

# Detailed specification
[dependencies."finos/morphir-examples"]
version = "^2.0.0"
features = ["extra-types"]
```

### Dependency Formats

#### Version String (Registry)

```toml
"morphir/sdk" = "^3.0.0"
```

#### Path (Local)

```toml
"my-org/common" = { path = "../common" }
```

#### Git

```toml
# By tag
"org/pkg" = { git = "https://github.com/org/pkg.git", tag = "v1.0.0" }

# By branch
"org/pkg" = { git = "https://github.com/org/pkg.git", branch = "main" }

# By commit
"org/pkg" = { git = "https://github.com/org/pkg.git", rev = "abc123" }
```

#### Detailed

```toml
[dependencies."org/pkg"]
version = "^2.0.0"
features = ["feature1", "feature2"]
optional = false
```

### Dependency Fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Semver constraint |
| `path` | string | Local path |
| `git` | string | Git repository URL |
| `tag` | string | Git tag |
| `branch` | string | Git branch |
| `rev` | string | Git commit hash |
| `features` | array | Optional features to enable |
| `optional` | bool | Optional dependency |

## `[dev-dependencies]` Section

Development-only dependencies (same format as `[dependencies]`).

```toml
[dev-dependencies]
"morphir/test-utils" = "^1.0.0"
"my-org/test-fixtures" = { path = "../test-fixtures" }
```

## `[extensions]` Section

Extension registration and configuration.

```toml
[extensions]
# WASM component (local path)
spark-codegen = { path = "./extensions/spark-codegen.wasm" }

# WASM component (URL)
scala-codegen = { url = "https://extensions.morphir.dev/scala-codegen-1.0.0.wasm" }

# Native executable
my-analyzer = { command = "./bin/my-analyzer", args = ["--mode", "jsonrpc"] }

# Disable auto-discovered extension
legacy-ext = { enabled = false }

# Extension-specific configuration
[extensions.spark-codegen.config]
spark_version = "3.5"
scala_version = "2.13"
```

### Extension Fields

| Field | Type | Description |
|-------|------|-------------|
| `path` | string | Local path to WASM or executable |
| `url` | string | URL to download extension |
| `command` | string | Executable command |
| `args` | array | Command arguments |
| `enabled` | bool | Enable/disable extension |
| `config` | table | Extension-specific configuration |

## `[tasks]` Section

Custom tasks and hooks.

```toml
[tasks]
# Simple command task
lint = "elm-review"

# Task with description
[tasks.integration]
description = "Run integration tests"
run = "./scripts/integration-tests.sh"

# Task with dependencies
[tasks.ci]
description = "Full CI pipeline"
depends = ["check", "test", "build"]

# Task with working directory
[tasks.docs]
description = "Generate documentation"
run = "morphir docs generate"
cwd = "./docs"

# Pre/post hooks for built-in tasks
[tasks."pre:build"]
run = "echo 'Starting build...'"

[tasks."post:build"]
run = "prettier --write .morphir-dist/"

[tasks."post:codegen"]
run = "./scripts/post-codegen.sh"
```

### Task Fields

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Human-readable description |
| `run` | string | Shell command to execute |
| `depends` | array | Task dependencies (run first) |
| `cwd` | string | Working directory |
| `env` | table | Environment variables |

### Built-in Tasks

| Task | Description |
|------|-------------|
| `build` | Compile project to IR |
| `check` | Lint and validate |
| `test` | Run tests |
| `codegen` | Generate code for targets |
| `pack` | Create distributable package |
| `publish` | Publish to registry |
| `clean` | Remove build artifacts |

### Hooks

Hooks extend built-in tasks:

| Hook | Timing |
|------|--------|
| `pre:<task>` | Before task runs |
| `post:<task>` | After task succeeds |

## `[test]` Section

Test configuration.

```toml
[test]
# Test directory
directory = "tests"

# Test patterns
include = ["**/*Test.elm", "**/*Spec.elm"]
exclude = ["**/helpers/**"]

# Test runner settings
timeout = 30000  # milliseconds
parallel = true
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `directory` | string | `"tests"` | Test directory |
| `include` | array | `["**/*Test.*"]` | Include patterns |
| `exclude` | array | `[]` | Exclude patterns |
| `timeout` | integer | `30000` | Test timeout (ms) |
| `parallel` | bool | `true` | Run tests in parallel |

## `[publish]` Section

Publishing configuration.

```toml
[publish]
# Registry URL
registry = "https://registry.morphir.dev"

# Include patterns
include = [
    "src/**/*.elm",
    "morphir.toml",
    "README.md",
    "LICENSE"
]

# Exclude patterns
exclude = [
    "**/*.test.elm",
    "**/Internal/**"
]
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `registry` | string | Default registry | Registry URL |
| `include` | array | Standard files | Files to include |
| `exclude` | array | `[]` | Files to exclude |

## Complete Example

### Single Project

```toml
[morphir]
version = "^4.0.0"

[project]
name = "my-org/order-domain"
version = "1.0.0"
description = "Order processing domain model"
authors = ["Jane Doe <jane@example.com>"]
license = "Apache-2.0"
source_directory = "src"
exposed_modules = ["Domain.Order", "Domain.Product", "Domain.Customer"]

[frontend]
language = "elm"

[frontend.elm]
elm_version = "0.19"

[codegen]
targets = ["typescript", "scala"]

[codegen.typescript]
module_format = "esm"

[codegen.scala]
package_prefix = "com.myorg.orders"

[dependencies]
"morphir/sdk" = "^3.0.0"
"my-org/common-types" = { path = "../common-types" }

[dev-dependencies]
"morphir/test-utils" = "^1.0.0"

[tasks.ci]
description = "CI pipeline"
depends = ["check", "test", "build", "codegen"]
```

### Workspace

```toml
[morphir]
version = "^4.0.0"

[workspace]
members = ["packages/*", "apps/*"]
exclude = ["packages/deprecated-*"]
default_member = "packages/core"
output_dir = ".morphir"

# Shared settings inherited by all projects
[frontend]
language = "elm"

[frontend.elm]
elm_version = "0.19"

[codegen]
targets = ["typescript"]

# Shared dependencies
[dependencies]
"morphir/sdk" = "^3.0.0"

[extensions]
spark-codegen = { path = "./extensions/spark-codegen.wasm" }

[tasks.ci]
description = "Workspace CI"
depends = ["check", "test", "build"]
```

## Validation Rules

### Required Fields

| Mode | Required Sections/Fields |
|------|-------------------------|
| Project | `[project]`, `project.name`, `project.version` |
| Workspace | `[workspace]`, `workspace.members` |

### Naming Constraints

| Field | Constraint |
|-------|------------|
| `project.name` | `^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$` |
| `project.version` | Valid semver |
| Module names | PascalCase, dot-separated |

### Path Constraints

| Field | Constraint |
|-------|------------|
| `source_directory` | Must exist, relative path |
| `output_directory` | Relative path |
| `dependencies.*.path` | Must contain `morphir.toml` |

## Error Messages

| Error | Description |
|-------|-------------|
| `E001` | Missing required field |
| `E002` | Invalid package name format |
| `E003` | Invalid version format |
| `E004` | Source directory not found |
| `E005` | Circular dependency detected |
| `E006` | Unknown extension |
| `E007` | Invalid glob pattern |
| `E008` | Duplicate project name in workspace |
