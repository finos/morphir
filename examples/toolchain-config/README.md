# Example Toolchain Configuration

This example demonstrates the toolchain configuration format for Morphir.

## Structure

The example shows:

1. **External toolchain (morphir-elm)** - A process-based toolchain that:
   - Uses the `path` backend (tool already in PATH)
   - Defines two tasks: `make` and `gen`
   - Supports multiple variants for code generation (Scala, JsonSchema, TypeScript)
   - Uses artifact references to connect tasks

2. **Custom validator** - A simple toolchain that:
   - Validates Morphir IR
   - Depends on the output of the `make` task

## Toolchain Configuration

### Toolchain Definition

```toml
[toolchain.morphir-elm]
version = "2.90.0"           # Optional version
working_dir = "."            # Working directory for tasks
timeout = "5m"               # Default timeout for all tasks
```

### Acquisition

```toml
[toolchain.morphir-elm.acquire]
backend = "path"              # How to acquire the tool (path, npx, npm, etc.)
executable = "morphir-elm"    # Executable name
```

### Tasks

```toml
[toolchain.morphir-elm.tasks.make]
exec = "morphir-elm"                        # Executable to run
args = ["make", "-o", "{outputs.ir}"]      # Arguments with variable substitution
fulfills = ["make"]                         # Targets this task fulfills
```

### Inputs and Outputs

Tasks can specify inputs (files or artifacts) and outputs:

```toml
# File inputs
[toolchain.morphir-elm.tasks.make.inputs]
files = ["elm.json", "src/**/*.elm"]

# Output artifacts
[toolchain.morphir-elm.tasks.make.outputs.ir]
path = "morphir-ir.json"
type = "morphir-ir"
```

### Artifact References

Tasks can reference outputs from other tasks:

```toml
[toolchain.morphir-elm.tasks.gen.inputs]
artifacts = { ir = "@morphir-elm/make:ir" }
```

This references the `ir` output from the `make` task in the `morphir-elm` toolchain.

### Variants

Tasks can support multiple variants:

```toml
[toolchain.morphir-elm.tasks.gen]
variants = ["Scala", "JsonSchema", "TypeScript"]
args = ["gen", "-i", "{inputs.ir}", "-o", "{outputs.dir}", "-t", "{variant}"]
```

The `{variant}` placeholder is substituted when running with a specific variant.

## Output Directory Structure

Task outputs are written to:

```
.morphir/
└── out/
    └── {toolchain}/
        └── {task}/
            ├── meta.json           # Task metadata (timing, exit code, etc.)
            ├── diagnostics.jsonl   # Errors and warnings (JSONL format)
            └── {output-files}      # Actual task outputs
```

## Usage

Once configured, tasks can be executed via:

```bash
# Run a target
morphir make

# Run with a variant
morphir gen:scala

# Run a workflow
morphir build
```
