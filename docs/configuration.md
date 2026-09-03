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
| 0 (lowest) | Built-in defaults | (compiled in) | Sensible defaults |
| 100 | System config | `/etc/morphir/morphir.toml` (`%PROGRAMDATA%\morphir\morphir.toml` on Windows) | System-wide settings |
| 200 | Global user config | Platform config directory or user-home `.morphir` directory | User preferences |
| 300 | Project or workspace primary | Root, hidden, or dot-config primary layout | Shared project settings |
| 350 | Selected workspace-member primary | Root, hidden, or dot-config primary layout in the member | Member settings |
| 400 | User override | Adjacent to a selected project, workspace, or member primary | Local overrides |
| 600 (highest) | Environment variables | `MORPHIR_*` | Runtime overrides |

Higher-priority sources override lower-priority ones for the same setting. Each configuration location accepts its TOML and YAML pair. If both exist, Morphir reports an ambiguity error instead of choosing one. See the [merge rules](spec/morphir-toml/morphir-toml-merge-rules.md) for the full algorithm.

## File Locations

### Project Configuration

Place `morphir.toml` or `morphir.yaml` in your project root:

```
my-project/
├── morphir.toml          # Primary configuration (morphir.yaml is also supported)
├── morphir.user.toml     # Adjacent personal override
└── src/
```

Or use the hidden style with `morphir workspace init --hidden`:

```
my-project/
├── .morphir/
│   ├── morphir.toml      # Primary configuration (morphir.yaml is also supported)
│   └── morphir.user.toml # Adjacent personal override
└── src/
```

The dot-config layout is also supported:

```
my-project/
├── .config/
│   └── morphir/
│       ├── config.toml      # Primary configuration (config.yaml is also supported)
│       └── config.user.toml # Adjacent personal override
└── src/
```

Choose one primary file from all six TOML and YAML candidates. Morphir reports an ambiguity error if more than one exists. Its adjacent override uses the matching base name: `morphir.user.*` beside `morphir.*`, or `config.user.*` beside `config.*`.

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

When the [`MORPHIR_HOME` environment variable](#special-environment-variables) is set, the user-home candidate on every platform becomes `$MORPHIR_HOME/morphir.toml` or `morphir.yaml` instead of the `.morphir` directory under the user home. The platform config-directory candidates are unaffected.

TOML example:

```toml
[ui]
theme = "dark"

[ir]
format_version = 4
```

YAML example:

```yaml
ui:
  theme: dark

ir:
  format_version: 4
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

# Out directory for every task in the workspace, relative to the workspace root
out_dir = ".morphir/out"
```

`out_dir` only applies when it is set in the workspace root configuration. See
[Out directory](design/out-directory.md) for how every task's output is laid
out under it, and how `-o` and `--out-dir` interact with it.

### [ir]

IR processing settings:

```toml
[ir]
# IR format version (1-10)
format_version = 3

# Enable strict validation
strict_mode = false

# Storage compile writes: single-file or document-tree
layout = "single-file"

# Serialization format: json or yaml
format = "json"
```

`mode` (`classic` or `vfs`) is a deprecated alias for `layout` (`classic` maps
to `single-file`, `vfs` maps to `document-tree`) and prints a warning; an
explicit `layout` wins if both are set.

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

CLI startup logging is currently configured through environment variables, not
through discovered `morphir.toml` or `morphir.yaml` files. Use:

```sh
export MORPHIR_LOGGING__LEVEL=info
export MORPHIR_LOGGING__FILE_LEVEL=debug
export MORPHIR_LOG_FILE=true
export MORPHIR_LOG_DIR=/path/to/logs
```

`MORPHIR_LOG_LEVEL` and `MORPHIR_LOG_FILE_LEVEL` remain compatibility aliases
for the two canonical level variables.

Configuration-file support for startup logging remains planned. Until it is
implemented, a `[logging]` table may be inspected by `morphir config`, but it
does not control the active logger.

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

### Special Environment Variables

Some environment variables control Morphir directly rather than overriding a configuration key:

| Variable | Purpose | Default |
|----------|---------|---------|
| `MORPHIR_HOME` | Relocates the Morphir home directory, which holds user-global state such as the tool, distribution, and extension registries and fallback log output; when set, caches also relocate under `$MORPHIR_HOME/cache` | `$HOME/.morphir` on Linux/macOS, `%USERPROFILE%\.morphir` on Windows |
| `MORPHIR_LOG_DIR` | Overrides the CLI log output directory | `$MORPHIR_HOME/logs/cli` |
| `MORPHIR_LOG_FILE` | Enables or disables local CLI file logging | `true` when Morphir Home resolves; otherwise console-only |
| `MORPHIR_OUT_DIR` | Relocates the out root every task writes under, resolved relative to the current directory | `<workspace_root>/.morphir/out`, or `[workspace].out_dir` if set |

Relocating the home directory is useful for testing, CI, or sandboxed environments where the real user home is unavailable or should stay untouched:

```sh
export MORPHIR_HOME=/tmp/morphir-test-home
```

An empty value is treated as unset.

## CLI Commands

Task output always lands under the out root (`<workspace>/.morphir/out` by
default). `-o` installs a task's declared outputs to another directory after
the run. `--out-dir` or `MORPHIR_OUT_DIR` relocates the root. See
[Out directory](design/out-directory.md) for the full layout.

### View Configuration

Show the resolved configuration:

```sh
# Human-readable format
morphir config show

# JSON format (for scripting)
morphir config show --json
```

See [Secrets](#secrets) for how credentials are displayed.

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

A user override is personal configuration that should not be committed to version control. It is adjacent to the selected primary configuration: `morphir.user.toml` or `morphir.user.yaml` for root and hidden layouts, or `config.user.toml` or `config.user.yaml` for the dot-config layout. A loader and `morphir workspace init` do not edit ignore files. Add the applicable adjacent `*.user.*` names to your repository's ignore policy yourself.

In a workspace, Morphir applies the workspace override before the selected member's override. Both use the layout of their own primary configuration, so the member override wins.

Common uses:
- Custom cache locations
- Personal UI preferences

Example:

```toml
# morphir.user.toml next to morphir.toml

[ui]
theme = "dark"
```

## Secrets

Never put credentials in a committed configuration file. The configuration format specifies a **secret reference** for this, written instead of the secret itself:

```toml
[registry]
token = { env = "GITHUB_TOKEN" }
password = { file = "~/.config/morphir/registry-password" }
command_token = { command = ["gh", "auth", "token"] }
keyring_token = { keyring = { service = "github.com", account = "damre" } }
```

```yaml
registry:
  token: { env: GITHUB_TOKEN }
  password: { file: "~/.config/morphir/registry-password" }
  command_token: { command: [gh, auth, token] }
  keyring_token: { keyring: { service: github.com, account: damre } }
```

The morphir-rust API, built with Rust 1.88, resolves one requested dotted key through `EffectiveConfig::resolve_secret` or `EffectiveConfig::resolve_secret_with`. It never resolves every reference eagerly. `env` reads a non-empty environment value. `file` reads non-empty UTF-8 text, removes one line ending, and resolves a relative path from the configuration file that supplied the winning value. A relative file reference requires that declaring configuration file. `~` expands to the current user's home directory.

`command` runs the array's program and arguments directly, without a shell or standard input. It runs from the directory of the configuration file that supplied the winning value. If there is no declaring file, it uses the process current directory. Successful standard output must be non-empty UTF-8 text after one line ending is removed. `keyring` reads an existing native keyring password for its service and account. It never writes to the keyring.

The resolver returns a protected secret. Formatting redacts it, ordinary serialization is unavailable, and callers need an explicit exposure operation to read it. Loading, validation, `morphir config show`, and `morphir config path` do not resolve references. Resolution failures identify the configuration key and safe source metadata without including secret text.

### How `morphir config show` displays values

`morphir config show` redacts sensitive values before printing them. Redaction is a key-name heuristic, not a check on the value's shape. Any configuration key whose name, case-insensitively and with `-` treated as `_`, contains `token`, `password`, `passwd`, `secret`, `credential`, `api_key`, `apikey`, `private_key`, or `access_key` has its entire value replaced with `<redacted>`. This applies to plain strings, secret-reference tables, and arbitrary nested values. The command does not resolve a reference.

Environment variables under a sensitive key are redacted the same way, whatever value they carry: `MORPHIR_REGISTRY__TOKEN='{"env":"GH_TOKEN"}'` also displays as `<redacted>`.

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
```
