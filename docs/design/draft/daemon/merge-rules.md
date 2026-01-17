---
title: Configuration Merge Rules
sidebar_label: Merge Rules
sidebar_position: 10
status: draft
---

# Configuration Merge Rules

This document specifies how configuration from multiple sources is merged and resolved.

## Merge Precedence

Configuration is resolved from multiple sources in this order (highest precedence first):

1. **Command-line flags**: `--config key=value`
2. **Environment variables**: `MORPHIR__SECTION__KEY`
3. **Workspace local config**: `./.config/morphir/config.toml`
4. **Project config**: `./morphir.toml` in project directory
5. **Workspace config**: `./morphir.toml` at workspace root
6. **Parent configs**: Walk up directory tree
7. **User config**: `~/.config/morphir/config.toml`
8. **System config**: `/etc/morphir/config.toml`

Higher precedence sources override lower precedence sources.

## Merge Strategies

Different configuration types use different merge strategies:

| Type | Strategy | Description |
|------|----------|-------------|
| Scalar | Replace | Higher precedence value replaces lower |
| Array | Replace (default) | Higher precedence array replaces entirely |
| Array | Append | Arrays are concatenated |
| Table | Deep merge | Tables are recursively merged |

### Scalar Values (Replace)

Scalar values (strings, numbers, booleans) are replaced entirely:

```toml
# User config (~/.config/morphir/config.toml)
[codegen]
output_format = "compact"

# Project config (./morphir.toml)
[codegen]
output_format = "pretty"

# Result: output_format = "pretty"
```

### Arrays (Replace by Default)

Arrays are replaced entirely by default:

```toml
# Workspace config
[codegen]
targets = ["typescript", "scala"]

# Project config
[codegen]
targets = ["spark"]

# Result: targets = ["spark"]
```

### Arrays (Append Mode)

To append instead of replace, use the `+` prefix:

```toml
# Workspace config
[codegen]
targets = ["typescript"]

# Project config
[codegen]
"+targets" = ["spark", "scala"]

# Result: targets = ["typescript", "spark", "scala"]
```

### Tables (Deep Merge)

Tables are recursively merged:

```toml
# Workspace config
[codegen.typescript]
module_format = "esm"
strict = true

# Project config
[codegen.typescript]
declaration = true

# Result:
# [codegen.typescript]
# module_format = "esm"
# strict = true
# declaration = true
```

## Section-Specific Rules

### `[project]` Section

The `[project]` section is **never inherited**. Each project must define its own:

- `name`
- `version`
- `source_directory`
- `exposed_modules`

These fields are project-specific and cannot be overridden from workspace or parent configs.

### `[workspace]` Section

The `[workspace]` section exists only at workspace root. It is **not inherited** by member projects.

### `[dependencies]` Section

Dependencies merge with these rules:

1. **Same package, different versions**: Project version wins
2. **Path vs version**: More specific (project) wins
3. **New dependencies**: Added to merged set

```toml
# Workspace config
[dependencies]
"morphir/sdk" = "^3.0.0"
"org/shared" = "^1.0.0"

# Project config
[dependencies]
"morphir/sdk" = "^3.1.0"  # Overrides workspace
"org/project-specific" = "^2.0.0"  # Added

# Result:
# "morphir/sdk" = "^3.1.0"
# "org/shared" = "^1.0.0"
# "org/project-specific" = "^2.0.0"
```

### `[codegen]` Section

Code generation settings merge deeply:

```toml
# Workspace config
[codegen]
targets = ["typescript"]
output_format = "pretty"

[codegen.typescript]
module_format = "esm"

# Project config
[codegen]
"+targets" = ["spark"]  # Append

[codegen.typescript]
strict = false  # Add to typescript config

[codegen.spark]
spark_version = "3.5"  # New target config

# Result:
# targets = ["typescript", "spark"]
# output_format = "pretty"
# [codegen.typescript]
# module_format = "esm"
# strict = false
# [codegen.spark]
# spark_version = "3.5"
```

### `[extensions]` Section

Extensions merge with these rules:

1. **Same extension ID**: Project config wins entirely
2. **Disabled extensions**: `enabled = false` prevents loading
3. **New extensions**: Added to merged set

```toml
# Workspace config
[extensions]
spark-codegen = { path = "./extensions/spark-codegen.wasm" }

[extensions.spark-codegen.config]
spark_version = "3.4"

# Project config
[extensions.spark-codegen.config]
spark_version = "3.5"  # Overrides

# Result: spark_version = "3.5"
```

### `[tasks]` Section

Tasks merge with these rules:

1. **Same task name**: Project definition wins
2. **Hooks**: All hooks at all levels run (workspace first, then project)
3. **Dependencies**: Resolved from merged task set

```toml
# Workspace config
[tasks.lint]
run = "elm-review"

[tasks."pre:build"]
run = "echo 'Workspace pre-build'"

# Project config
[tasks.lint]
run = "elm-review --fix"  # Overrides workspace

[tasks."pre:build"]
run = "echo 'Project pre-build'"  # Both run!

# Result:
# - lint runs: "elm-review --fix"
# - pre:build runs BOTH (workspace first, then project)
```

### `[frontend]` Section

Frontend settings merge deeply, with rules evaluated in order:

```toml
# Workspace config
[frontend]
language = "elm"

[[frontend.rules]]
pattern = "**/*.morphir"
language = "morphir-dsl"

# Project config
[frontend]
# language inherited from workspace

[[frontend.rules]]
pattern = "src/legacy/**"
language = "elm"  # Project rules evaluated first

# Result: Project rules checked first, then workspace rules
```

## Environment Variables

Environment variables override file configuration using this naming convention:

```
MORPHIR__<SECTION>__<KEY>
```

### Naming Rules

- Sections and keys are uppercase
- Dots become double underscores
- Hyphens become single underscores

### Examples

| Environment Variable | Configuration Path |
|---------------------|-------------------|
| `MORPHIR__PROJECT__NAME` | `project.name` |
| `MORPHIR__CODEGEN__OUTPUT_FORMAT` | `codegen.output_format` |
| `MORPHIR__CODEGEN__TYPESCRIPT__STRICT` | `codegen.typescript.strict` |
| `MORPHIR__FRONTEND__LANGUAGE` | `frontend.language` |

### Type Coercion

Environment variables are strings. They are coerced to the expected type:

| Expected Type | Coercion |
|--------------|----------|
| string | As-is |
| integer | Parse as integer |
| boolean | `"true"`, `"1"`, `"yes"` → true; else false |
| array | JSON array or comma-separated |

```bash
# String
export MORPHIR__PROJECT__NAME="my-org/my-project"

# Integer
export MORPHIR__WORKSPACE__MAX_JOBS="4"

# Boolean
export MORPHIR__IR__STRICT_MODE="true"

# Array (JSON)
export MORPHIR__CODEGEN__TARGETS='["typescript","scala"]'

# Array (comma-separated)
export MORPHIR__CODEGEN__TARGETS="typescript,scala"
```

## Command-Line Overrides

Command-line flags have highest precedence:

```bash
# Override single value
morphir build --config codegen.output_format=compact

# Override nested value
morphir build --config codegen.typescript.strict=false

# Override array (JSON)
morphir build --config 'codegen.targets=["spark"]'

# Multiple overrides
morphir build \
  --config codegen.output_format=compact \
  --config ir.strict_mode=true
```

## Merge Algorithm

```
function mergeConfig(sources: ConfigSource[]): Config {
    result = {}

    // Process sources from lowest to highest precedence
    for source in sources.reverse() {
        for section in source.sections {
            if section.name == "project" || section.name == "workspace" {
                // Never inherit project/workspace sections
                if source.isProjectConfig {
                    result[section.name] = section.value
                }
            } else {
                result[section.name] = mergeSection(
                    result[section.name],
                    section.value,
                    section.name
                )
            }
        }
    }

    return result
}

function mergeSection(base: Value, overlay: Value, path: string): Value {
    if overlay is null {
        return base
    }

    if base is null {
        return overlay
    }

    if overlay is Scalar {
        return overlay  // Replace
    }

    if overlay is Array {
        if path.startsWith("+") {
            return concat(base, overlay)  // Append
        }
        return overlay  // Replace
    }

    if overlay is Table {
        result = copy(base)
        for key, value in overlay {
            result[key] = mergeSection(result[key], value, key)
        }
        return result
    }
}
```

## Examples

### Example 1: Workspace with Project Override

**Workspace config** (`workspace/morphir.toml`):
```toml
[morphir]
version = "^4.0.0"

[workspace]
members = ["packages/*"]

[codegen]
targets = ["typescript"]
output_format = "pretty"

[codegen.typescript]
module_format = "esm"
```

**Project config** (`workspace/packages/api/morphir.toml`):
```toml
[project]
name = "my-org/api"
version = "1.0.0"

[codegen]
"+targets" = ["openapi"]  # Append

[codegen.typescript]
strict = true  # Add to typescript config
```

**Resolved config for `packages/api`**:
```toml
[morphir]
version = "^4.0.0"

[project]
name = "my-org/api"
version = "1.0.0"

[codegen]
targets = ["typescript", "openapi"]
output_format = "pretty"

[codegen.typescript]
module_format = "esm"
strict = true
```

### Example 2: Environment Override

**Project config**:
```toml
[codegen]
targets = ["typescript"]

[codegen.typescript]
strict = true
```

**Environment**:
```bash
export MORPHIR__CODEGEN__TARGETS="spark,scala"
export MORPHIR__CODEGEN__TYPESCRIPT__STRICT="false"
```

**Resolved config**:
```toml
[codegen]
targets = ["spark", "scala"]  # From env

[codegen.typescript]
strict = false  # From env
```

### Example 3: User Defaults

**System config** (`/etc/morphir/config.toml`):
```toml
[codegen]
output_format = "compact"
```

**User config** (`~/.config/morphir/config.toml`):
```toml
[codegen]
output_format = "pretty"

[ir]
include_source_locations = true
```

**Project config** (`./morphir.toml`):
```toml
[project]
name = "my-org/project"
version = "1.0.0"

[codegen]
targets = ["typescript"]
```

**Resolved config**:
```toml
[project]
name = "my-org/project"
version = "1.0.0"

[codegen]
targets = ["typescript"]
output_format = "pretty"  # From user config

[ir]
include_source_locations = true  # From user config
```

## Debugging Configuration

### Show Resolved Config

```bash
# Show fully resolved configuration
morphir config show

# Show specific section
morphir config show codegen

# Show where values come from
morphir config show --sources
```

### Example Output

```
$ morphir config show --sources

[project]
  name = "my-org/api"                    # ./morphir.toml
  version = "1.0.0"                      # ./morphir.toml

[codegen]
  targets = ["typescript", "openapi"]    # merged
    - "typescript"                       # ../morphir.toml (workspace)
    - "openapi"                          # ./morphir.toml (append)
  output_format = "pretty"               # ../morphir.toml (workspace)

[codegen.typescript]
  module_format = "esm"                  # ../morphir.toml (workspace)
  strict = true                          # ./morphir.toml
```
