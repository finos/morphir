# Morphir Configuration Guide

This guide explains how to configure the Morphir CLI and tooling.

## Quick Start

Initialize a new workspace:

```sh
morphir workspace init
```

This creates a `morphir.toml` file and `.morphir/` directory. Edit `morphir.toml` to customize settings.

## Configuration Files

Morphir loads configuration from multiple sources, merged in priority order:

| Priority | Source | Path | Purpose |
|----------|--------|------|---------|
| 1 (lowest) | Built-in defaults | (compiled in) | Sensible defaults |
| 2 | System config | `/etc/morphir/morphir.toml` (`%PROGRAMDATA%\morphir\morphir.toml` on Windows) | System-wide settings |
| 3 | Global user config | Platform config directory or user-home `.morphir` directory | User preferences |
| 4 | Project config | `morphir.toml`, `morphir.yaml`, or the corresponding hidden path | Project settings |
| 5 | User override | `.morphir/morphir.user.toml` or `.morphir/morphir.user.yaml` | Local overrides (gitignored) |
| 6 (highest) | Environment variables | `MORPHIR_*` | Runtime overrides |

Higher-priority sources override lower-priority ones for the same setting. Every file source accepts either a `morphir.toml` or a `morphir.yaml` serialization at the same location; if both exist, Morphir reports an ambiguity error instead of choosing one. See the [merge rules](spec/morphir-toml/morphir-toml-merge-rules.md) for the full algorithm.

## File Locations

### Project Configuration

Place `morphir.toml` or `morphir.yaml` in your project root:

```
my-project/
├── morphir.toml          # Project configuration (morphir.yaml is also supported)
├── .morphir/
│   └── morphir.user.toml # User overrides (gitignored)
└── src/
```

Or use the hidden style with `morphir workspace init --hidden`:

```
my-project/
├── .morphir/
│   ├── morphir.toml      # Project configuration (morphir.yaml is also supported)
│   └── morphir.user.toml # User overrides
└── src/
```

### Global User Configuration

Create one global user file for settings that apply to all projects.

On Linux and other XDG systems, Morphir checks:

- `$XDG_CONFIG_HOME/morphir/morphir.toml` or `morphir.yaml` when `XDG_CONFIG_HOME` is an absolute path
- `$HOME/.config/morphir/morphir.toml` or `morphir.yaml` when `XDG_CONFIG_HOME` is unset, empty, or relative
- `$HOME/.morphir/morphir.toml` or `morphir.yaml`

On macOS, Morphir checks a valid `$XDG_CONFIG_HOME` first. Without it, the standard location is `$HOME/Library/Application Support/morphir/morphir.toml` or `morphir.yaml`. The `$HOME/.morphir` alternative also applies.

On Windows, Morphir checks:

- `%APPDATA%\morphir\morphir.toml` or `morphir.yaml`, resolved through the Windows `FOLDERID_RoamingAppData` known folder
- `%USERPROFILE%\.morphir\morphir.toml` or `morphir.yaml`, resolved through `FOLDERID_Profile`

The paths are alternatives at the same precedence. If more than one candidate exists, Morphir reports an ambiguity error.

TOML example:

```toml
[logging]
level = "debug"

[ui]
theme = "dark"
```

YAML example:

```yaml
logging:
  level: debug

ui:
  theme: dark
```

### System Configuration

Administrators can create `/etc/morphir/morphir.toml` (or `morphir.yaml`) for organization-wide defaults. On Windows the system location is `%PROGRAMDATA%\morphir\morphir.toml`, which falls back to `C:\ProgramData\morphir\morphir.toml` when `PROGRAMDATA` is not set.

## Configuration Sections

### [morphir]

Core Morphir settings:

```toml
[morphir]
# Morphir IR version constraint (semver syntax)
version = "^3.0.0"
```

### [workspace]

Workspace paths:

```toml
[workspace]
# Workspace root (usually left empty)
root = ""

# Output directory for generated artifacts
output_dir = ".morphir"
```

### [ir]

IR processing settings:

```toml
[ir]
# IR format version (1-10)
format_version = 3

# Enable strict validation
strict_mode = false
```

### [codegen]

Code generation settings:

```toml
[codegen]
# Target languages
targets = ["go", "typescript"]

# Custom template directory
template_dir = ""

# Output format: pretty, compact, minified
output_format = "pretty"
```

### [cache]

Caching settings:

```toml
[cache]
# Enable caching
enabled = true

# Cache directory (empty = default)
dir = ""

# Max cache size in bytes (0 = unlimited)
max_size = 0
```

### [logging]

Logging settings:

```toml
[logging]
# Log level: debug, info, warn, error
level = "info"

# Log format: text, json
format = "text"

# Log file (empty = stderr)
file = ""
```

### [ui]

UI settings:

```toml
[ui]
# Enable colored output
color = true

# Enable interactive mode
interactive = true

# Theme: default, light, dark
theme = "default"
```

## Environment Variables

Override any setting with environment variables using the `MORPHIR_` prefix. A double underscore (`__`) separates nesting levels; single underscores stay part of the key name:

```sh
# Override logging level
export MORPHIR_LOGGING__LEVEL=debug

# Disable caching
export MORPHIR_CACHE__ENABLED=false

# Set IR format version
export MORPHIR_IR__FORMAT_VERSION=3

# Disable colors
export MORPHIR_UI__COLOR=false
```

Mapping examples:
- `logging.level` → `MORPHIR_LOGGING__LEVEL`
- `ir.format_version` → `MORPHIR_IR__FORMAT_VERSION`
- `codegen.go.package` → `MORPHIR_CODEGEN__GO__PACKAGE`

Values are typed mechanically: `true` and `false` become booleans, integers become numbers, values that start with `[` or `{` and parse as JSON become arrays or objects, and anything else stays a string. Key segments are lower-cased.

## CLI Commands

### View Configuration

Show the resolved configuration:

```sh
# Human-readable format
morphir config show

# JSON format (for scripting)
morphir config show --json
```

Credentials are redacted before printing: any key containing `token`, `password`, `secret`, `credential`, or `api_key` is shown as `<redacted>`.

### Show Configuration Sources

See which files were loaded:

```sh
# Human-readable format
morphir config path

# JSON format
morphir config path --json
```

Example output:

```
Configuration sources (in priority order):

  [✓] project
      Path: /home/user/my-project/morphir.toml
      Status: loaded
      Priority: 300

  [✗] global
      Path: /home/user/.config/morphir/morphir.toml
      Status: not found
      Priority: 200
```

### Initialize Workspace

Create a new workspace:

```sh
# In current directory
morphir workspace init

# In specific directory
morphir workspace init /path/to/project

# With hidden config style
morphir workspace init --hidden

# With custom project name
morphir workspace init --name my-project

# JSON output (for scripting)
morphir workspace init --json
```

## User Overrides

The `.morphir/morphir.user.toml` file (or `.morphir/morphir.user.yaml`; not both) is for personal settings that shouldn't be committed to version control. It's automatically added to `.morphir/.gitignore`. In a workspace, Morphir also applies the override in the selected member's `.morphir` directory after the workspace-level one.

Common uses:
- Debug logging during development
- Custom cache locations
- Personal UI preferences

Example:

```toml
# .morphir/morphir.user.toml

[logging]
level = "debug"
file = ".morphir/debug.log"

[ui]
theme = "dark"
```

## Validation

The configuration system validates values and reports errors and warnings:

- **Errors** (fatal): Invalid log level, negative cache size, malformed paths
- **Warnings** (non-fatal): Unknown theme, unusual IR version

Invalid configuration prevents the CLI from running. Warnings are displayed but don't block execution.

## Examples

### Minimal Configuration

```toml
[morphir]
version = "^3.0.0"

[codegen]
targets = ["go"]
```

### Full Configuration

See [examples/morphir.toml](../examples/morphir.toml) for a fully commented example.

### CI/CD Configuration

For CI environments, use environment variables:

```yaml
# GitHub Actions example
env:
  MORPHIR_LOGGING__LEVEL: warn
  MORPHIR_UI__COLOR: false
  MORPHIR_UI__INTERACTIVE: false
  MORPHIR_CACHE__DIR: /tmp/morphir-cache
```

### Multi-Target Code Generation

```toml
[codegen]
targets = ["go", "typescript", "scala"]
output_format = "pretty"

[logging]
level = "info"
```
