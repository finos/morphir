---
title: Environment Variables
sidebar_label: Environment
sidebar_position: 11
status: draft
---

# Environment Variables

This document specifies all environment variables recognized by Morphir.

## Configuration Override Variables

Environment variables can override any configuration value using the naming convention:

```
MORPHIR__<SECTION>__<KEY>
```

See [Merge Rules](./merge-rules.md) for details on how environment overrides work.

## Core Environment Variables

### `MORPHIR_HOME`

The Morphir home directory for user-level data.

| Aspect | Value |
|--------|-------|
| Default (Linux/macOS) | `$XDG_DATA_HOME/morphir` or `~/.local/share/morphir` |
| Default (Windows) | `%LOCALAPPDATA%\morphir` |
| Contains | User extensions, cache, global config |

```bash
export MORPHIR_HOME="/opt/morphir"
```

### `MORPHIR_CONFIG_HOME`

The Morphir configuration directory.

| Aspect | Value |
|--------|-------|
| Default (Linux/macOS) | `$XDG_CONFIG_HOME/morphir` or `~/.config/morphir` |
| Default (Windows) | `%APPDATA%\morphir` |
| Contains | `config.toml`, credentials |

```bash
export MORPHIR_CONFIG_HOME="/etc/morphir"
```

### `MORPHIR_CACHE_HOME`

The Morphir cache directory.

| Aspect | Value |
|--------|-------|
| Default (Linux/macOS) | `$XDG_CACHE_HOME/morphir` or `~/.cache/morphir` |
| Default (Windows) | `%LOCALAPPDATA%\morphir\cache` |
| Contains | Downloaded dependencies, build cache |

```bash
export MORPHIR_CACHE_HOME="/var/cache/morphir"
```

## Daemon Variables

### `MORPHIR_DAEMON_URL`

URL of a running Morphir daemon to connect to.

| Aspect | Value |
|--------|-------|
| Default | None (start embedded daemon) |
| Format | `http://host:port` or `unix:///path/to/socket` |

```bash
# Connect to local daemon
export MORPHIR_DAEMON_URL="http://localhost:3000"

# Connect to Unix socket
export MORPHIR_DAEMON_URL="unix:///tmp/morphir.sock"

# Connect to remote daemon
export MORPHIR_DAEMON_URL="http://build-server:3000"
```

### `MORPHIR_DAEMON_AUTO_START`

Whether to automatically start a daemon if none is running.

| Aspect | Value |
|--------|-------|
| Default | `true` |
| Values | `true`, `false`, `1`, `0` |

```bash
export MORPHIR_DAEMON_AUTO_START="false"
```

### `MORPHIR_DAEMON_TIMEOUT`

Timeout for daemon connections in milliseconds.

| Aspect | Value |
|--------|-------|
| Default | `30000` (30 seconds) |
| Format | Integer (milliseconds) |

```bash
export MORPHIR_DAEMON_TIMEOUT="60000"
```

### `MORPHIR_DAEMON_SHUTDOWN_TIMEOUT`

How long the daemon waits before shutting down when idle.

| Aspect | Value |
|--------|-------|
| Default | `3600000` (1 hour) |
| Format | Integer (milliseconds) |

```bash
# Keep daemon running for 8 hours
export MORPHIR_DAEMON_SHUTDOWN_TIMEOUT="28800000"

# Never auto-shutdown
export MORPHIR_DAEMON_SHUTDOWN_TIMEOUT="0"
```

## Build Variables

### `MORPHIR_PARALLEL`

Enable parallel builds.

| Aspect | Value |
|--------|-------|
| Default | `true` |
| Values | `true`, `false` |

```bash
export MORPHIR_PARALLEL="false"
```

### `MORPHIR_MAX_JOBS`

Maximum number of parallel build jobs.

| Aspect | Value |
|--------|-------|
| Default | Number of CPU cores |
| Format | Integer |

```bash
export MORPHIR_MAX_JOBS="4"
```

### `MORPHIR_INCREMENTAL`

Enable incremental builds.

| Aspect | Value |
|--------|-------|
| Default | `true` |
| Values | `true`, `false` |

```bash
export MORPHIR_INCREMENTAL="false"
```

## Output Variables

### `MORPHIR_COLOR`

Control colored output.

| Aspect | Value |
|--------|-------|
| Default | `auto` |
| Values | `auto`, `always`, `never` |

```bash
export MORPHIR_COLOR="never"
```

### `MORPHIR_LOG_LEVEL`

Logging verbosity level.

| Aspect | Value |
|--------|-------|
| Default | `info` |
| Values | `error`, `warn`, `info`, `debug`, `trace` |

```bash
export MORPHIR_LOG_LEVEL="debug"
```

### `MORPHIR_LOG_FORMAT`

Log output format.

| Aspect | Value |
|--------|-------|
| Default | `text` |
| Values | `text`, `json` |

```bash
export MORPHIR_LOG_FORMAT="json"
```

### `MORPHIR_QUIET`

Suppress non-essential output.

| Aspect | Value |
|--------|-------|
| Default | `false` |
| Values | `true`, `false` |

```bash
export MORPHIR_QUIET="true"
```

## Registry Variables

### `MORPHIR_REGISTRY`

Default package registry URL.

| Aspect | Value |
|--------|-------|
| Default | `https://registry.morphir.dev` |
| Format | URL |

```bash
export MORPHIR_REGISTRY="https://internal-registry.company.com"
```

### `MORPHIR_REGISTRY_TOKEN`

Authentication token for the registry.

| Aspect | Value |
|--------|-------|
| Default | None |
| Format | String (token) |

```bash
export MORPHIR_REGISTRY_TOKEN="ghp_xxxxxxxxxxxx"
```

### `MORPHIR_REGISTRY_USERNAME`

Username for registry authentication.

| Aspect | Value |
|--------|-------|
| Default | None |
| Format | String |

```bash
export MORPHIR_REGISTRY_USERNAME="myuser"
```

### `MORPHIR_REGISTRY_PASSWORD`

Password for registry authentication.

| Aspect | Value |
|--------|-------|
| Default | None |
| Format | String |

```bash
export MORPHIR_REGISTRY_PASSWORD="mypassword"
```

## Extension Variables

### `MORPHIR_EXTENSIONS_PATH`

Additional paths to search for extensions.

| Aspect | Value |
|--------|-------|
| Default | None |
| Format | Colon-separated paths (Unix) or semicolon-separated (Windows) |

```bash
export MORPHIR_EXTENSIONS_PATH="/opt/morphir/extensions:/home/user/my-extensions"
```

### `MORPHIR_EXTENSION_TIMEOUT`

Timeout for extension operations in milliseconds.

| Aspect | Value |
|--------|-------|
| Default | `30000` (30 seconds) |
| Format | Integer (milliseconds) |

```bash
export MORPHIR_EXTENSION_TIMEOUT="60000"
```

## CI/CD Variables

### `CI`

Standard CI environment indicator.

| Aspect | Value |
|--------|-------|
| Default | None |
| Effect | Disables interactive prompts, enables CI-friendly output |

```bash
export CI="true"
```

### `MORPHIR_CI`

Morphir-specific CI mode.

| Aspect | Value |
|--------|-------|
| Default | Value of `CI` |
| Effect | Same as `CI` |

### `MORPHIR_NO_INTERACTIVE`

Disable interactive prompts.

| Aspect | Value |
|--------|-------|
| Default | `false` (or `true` if `CI` is set) |
| Values | `true`, `false` |

```bash
export MORPHIR_NO_INTERACTIVE="true"
```

## Debugging Variables

### `MORPHIR_DEBUG`

Enable debug mode.

| Aspect | Value |
|--------|-------|
| Default | `false` |
| Effect | Verbose logging, stack traces, debug endpoints |

```bash
export MORPHIR_DEBUG="true"
```

### `MORPHIR_TRACE`

Enable trace-level debugging.

| Aspect | Value |
|--------|-------|
| Default | `false` |
| Effect | Extremely verbose output, performance logging |

```bash
export MORPHIR_TRACE="true"
```

### `MORPHIR_PROFILE`

Enable performance profiling.

| Aspect | Value |
|--------|-------|
| Default | `false` |
| Effect | Outputs timing information, generates profiles |

```bash
export MORPHIR_PROFILE="true"
```

## Platform-Specific Variables

### Linux/macOS

```bash
# XDG Base Directory Specification
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
```

Morphir respects XDG variables when `MORPHIR_*` equivalents are not set.

### Windows

```cmd
REM Standard Windows locations
set LOCALAPPDATA=%USERPROFILE%\AppData\Local
set APPDATA=%USERPROFILE%\AppData\Roaming
```

## Configuration Override Examples

### Override `[codegen]` Settings

```bash
# Override targets array
export MORPHIR__CODEGEN__TARGETS='["typescript","spark"]'

# Override output format
export MORPHIR__CODEGEN__OUTPUT_FORMAT="compact"

# Override nested TypeScript setting
export MORPHIR__CODEGEN__TYPESCRIPT__STRICT="false"
```

### Override `[ir]` Settings

```bash
export MORPHIR__IR__FORMAT_VERSION="4"
export MORPHIR__IR__STRICT_MODE="true"
export MORPHIR__IR__MODE="vfs"
```

### Override `[frontend]` Settings

```bash
export MORPHIR__FRONTEND__LANGUAGE="morphir-dsl"
```

## Environment File

Morphir supports `.env` files in the project root:

```bash
# .env file in project root
MORPHIR_LOG_LEVEL=debug
MORPHIR_PARALLEL=false
MORPHIR__CODEGEN__OUTPUT_FORMAT=compact
```

### `.env` File Loading Order

1. `.env` (always loaded)
2. `.env.local` (local overrides, gitignored)
3. `.env.{environment}` (e.g., `.env.production`)
4. `.env.{environment}.local` (local overrides for environment)

The `environment` is determined by `MORPHIR_ENV` or defaults to `development`.

```bash
export MORPHIR_ENV="production"
```

## Variable Reference Table

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `MORPHIR_HOME` | path | XDG default | Morphir data directory |
| `MORPHIR_CONFIG_HOME` | path | XDG default | Configuration directory |
| `MORPHIR_CACHE_HOME` | path | XDG default | Cache directory |
| `MORPHIR_DAEMON_URL` | url | None | Daemon connection URL |
| `MORPHIR_DAEMON_AUTO_START` | bool | `true` | Auto-start daemon |
| `MORPHIR_DAEMON_TIMEOUT` | int | `30000` | Connection timeout (ms) |
| `MORPHIR_DAEMON_SHUTDOWN_TIMEOUT` | int | `3600000` | Idle shutdown timeout (ms) |
| `MORPHIR_PARALLEL` | bool | `true` | Enable parallel builds |
| `MORPHIR_MAX_JOBS` | int | CPU count | Max parallel jobs |
| `MORPHIR_INCREMENTAL` | bool | `true` | Enable incremental builds |
| `MORPHIR_COLOR` | enum | `auto` | Color output mode |
| `MORPHIR_LOG_LEVEL` | enum | `info` | Log verbosity |
| `MORPHIR_LOG_FORMAT` | enum | `text` | Log format |
| `MORPHIR_QUIET` | bool | `false` | Suppress output |
| `MORPHIR_REGISTRY` | url | Default | Registry URL |
| `MORPHIR_REGISTRY_TOKEN` | string | None | Registry auth token |
| `MORPHIR_EXTENSIONS_PATH` | paths | None | Extension search paths |
| `MORPHIR_EXTENSION_TIMEOUT` | int | `30000` | Extension timeout (ms) |
| `CI` | bool | None | CI environment |
| `MORPHIR_DEBUG` | bool | `false` | Debug mode |
| `MORPHIR_TRACE` | bool | `false` | Trace mode |
| `MORPHIR_PROFILE` | bool | `false` | Profiling mode |
| `MORPHIR_ENV` | string | `development` | Environment name |
