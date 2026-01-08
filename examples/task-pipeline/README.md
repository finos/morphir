# Task Pipeline Example

This example demonstrates task configuration in Morphir.

## Usage

List all configured tasks:

```bash
# Table format (default)
morphir tasks

# Or equivalently
morphir task list

# JSON format
morphir task list --json

# Filter JSON properties
morphir task list --json --properties name,kind,depends_on
```

## Task Overview

This example includes various task types:

### Intrinsic Tasks (Built-in Actions)

| Task | Action | Description |
|------|--------|-------------|
| `compile` | `morphir.pipeline.compile` | Compile source to IR |
| `validate` | `morphir.pipeline.validate` | Validate generated IR |
| `analyze` | `morphir.analyzer.run` | Run static analysis |
| `report` | `morphir.report.summary` | Generate summary report |

### Command Tasks (External Commands)

| Task | Command | Description |
|------|---------|-------------|
| `setup` | `echo ...` | Setup build environment |
| `test` | `go test ./...` | Run Go tests |
| `lint` | `golangci-lint run` | Run linter |
| `codegen` | `morphir gen` | Generate Go code |
| `clean` | `rm -rf` | Clean build artifacts |

### Composite Tasks (Orchestration)

| Task | Dependencies | Description |
|------|--------------|-------------|
| `build` | setup, lint | Full build pipeline with hooks |
| `ci` | build, test, analyze | Complete CI pipeline |

## Task Configuration Features

The `morphir.toml` demonstrates:

- **Task kinds**: `intrinsic` vs `command`
- **Dependencies**: `depends_on = ["task1", "task2"]`
- **Hooks**: `pre` and `post` task execution
- **I/O declarations**: `inputs` and `outputs` globs
- **Parameters**: `[tasks.name.params]` section
- **Environment variables**: `[tasks.name.env]` section
- **Mount permissions**: `[tasks.name.mounts]` section
