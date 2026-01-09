# Golang Binding Module

This module provides Go code generation from Morphir IR, following the patterns established by the WIT binding.

## Status

**✅ MVP Implementation Complete**

The golang binding now has a working implementation that:
- Converts Morphir IR modules to Go packages
- Generates Go source code (types, interfaces, type aliases)
- Creates `go.mod` files for single modules
- Creates `go.work` files for multi-module workspaces
- Provides deterministic output with diagnostics
- Integrates with the Morphir toolchain framework as a native toolchain

### What Works

- **Type Conversion**: Type aliases and simple custom types (structs)
- **Code Generation**: Go source files with proper formatting (gofmt)
- **Module Layout**: Single and multi-module workspace generation
- **Diagnostics**: Warnings for unsupported features
- **Testing**: Comprehensive unit tests for domain model and pipeline

### Current Limitations (MVP)

- **Function Bodies**: Functions are generated as stubs with `panic("not implemented")`
- **Sum Types**: Multi-constructor custom types generate interfaces (not full sealed variant pattern)
- **Type Mapping**: Limited type expression support (basic references and variables)
- **Package Naming**: Simple package naming strategy (needs refinement)

## Architecture

The golang binding follows the pipeline architecture pattern:

- **make**: Frontend compilation (future: Go source → Morphir IR)
- **gen**: Backend generation (Morphir IR → Go code)
- **build**: Full pipeline (orchestrates make + gen)

## Package Structure

```
pkg/bindings/golang/
├── doc.go              # Package documentation
├── go.mod              # Module definition
├── go.sum              # Dependency checksums
├── pipeline/           # Pipeline step implementations
│   ├── doc.go          # Pipeline documentation
│   ├── types.go        # Input/output types for steps
│   ├── diagnostics.go  # Diagnostic codes and helpers
│   ├── make.go         # Make step (stub)
│   ├── gen.go          # Gen step (implemented)
│   └── build.go        # Build step (stub)
├── toolchain/          # Toolchain adapter for framework integration
│   ├── toolchain.go    # Toolchain definition and handlers
│   └── toolchain_test.go # Toolchain tests
├── domain/             # Domain types for Go code generation
│   └── doc.go          # Domain model documentation
└── internal/           # Internal implementation details
    └── doc.go          # Internal package documentation
```

## Pipeline Steps

### Make Step (Not Yet Implemented)

Future: Compiles Go source code to Morphir IR using `go/parser` and `go/types`.

### Gen Step (Implemented)

Generates Go code from Morphir IR:
- **Types**: Structs, interfaces, type aliases
- **Functions**: Exported function signatures (stubs for MVP)
- **Modules**: Go packages with proper structure
- **Module Files**: go.mod and optional go.work

The gen step:
1. Converts IR to Go domain model (`domain` package)
2. Emits Go source code with gofmt formatting
3. Creates module metadata files
4. Reports diagnostics for unsupported features

### Build Step (Stub)

Orchestrates the full pipeline:
1. Load Morphir IR from file
2. Execute gen step
3. Write generated files to VFS
4. Aggregate diagnostics

## Toolchain Integration

The golang binding is available as a native toolchain through the Morphir toolchain framework, following the same pattern as the WIT binding.

### Registration

```go
import (
    "github.com/finos/morphir/pkg/toolchain"
    golangToolchain "github.com/finos/morphir/pkg/bindings/golang/toolchain"
)

// Create a registry and register the Go toolchain
registry := toolchain.NewRegistry()
golangToolchain.Register(registry)

// Access the registered toolchain
tc, ok := registry.GetToolchain("golang")
```

### Available Tasks

| Task | Description | Status |
|------|-------------|--------|
| `make` | Compile Go source to Morphir IR | Not yet implemented |
| `gen` | Generate Go source code from Morphir IR | ✅ Working |
| `build` | Full pipeline (load IR + gen) | Stub |

### Task Options

#### Gen Task Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `modulePath` | string | Yes | Go module path (e.g., `github.com/example/app`) |
| `outputDir` | string | Yes | Output directory for generated files |
| `module` | `ir.ModuleDefinition` | Yes | Morphir IR module to generate from |
| `workspace` | bool | No | Generate `go.work` for multi-module workspace |
| `warningsAsErrors` | bool | No | Treat warnings as errors |

#### Make Task Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `source` | string | No | Go source code as string |
| `filePath` | string | No | Path to Go source file |
| `warningsAsErrors` | bool | No | Treat warnings as errors |
| `strictMode` | bool | No | Fail on unsupported constructs |

#### Build Task Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `irPath` | string | Yes | Path to Morphir IR JSON file |
| `outputDir` | string | Yes | Output directory for generated files |
| `modulePath` | string | Yes | Go module path for generated code |
| `workspace` | bool | No | Generate `go.work` for multi-module workspace |
| `warningsAsErrors` | bool | No | Treat warnings as errors |
| `strictMode` | bool | No | Fail on unsupported constructs |

### Programmatic Usage

```go
import (
    "github.com/finos/morphir/pkg/bindings/golang/toolchain"
    "github.com/finos/morphir/pkg/pipeline"
    tc "github.com/finos/morphir/pkg/toolchain"
    "github.com/finos/morphir/pkg/vfs"
)

// Set up context
mount := vfs.NewOSMount("work", vfs.MountRW, "/path/to/project", vfs.MustVPath("/"))
overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
ctx := pipeline.NewContext("/path/to/project", 0, pipeline.ModeDefault, overlay)

// Get the toolchain
golang := toolchain.GolangToolchain()

// Find the gen task
var genTask *tc.TaskDef
for i := range golang.Tasks {
    if golang.Tasks[i].Name == "gen" {
        genTask = &golang.Tasks[i]
        break
    }
}

// Execute the gen task
input := tc.TaskInput{
    Options: map[string]any{
        "modulePath": "github.com/example/generated",
        "outputDir":  "/output",
        "module":     myIRModule,
    },
}

result := genTask.Handler(ctx, input)
if result.Error != nil {
    // Handle error
}

// Access generated files from result.Outputs["generatedFiles"]
```

## Diagnostic Codes

- **GO001**: Type mapping information lost
- **GO002**: Unsupported IR construct
- **GO003**: Name collision in generated code
- **GO004**: Invalid Go identifier generated
- **GO005**: Module structure conflict
- **GO006**: IR parsing error
- **GO007**: General code generation error
- **GO008**: Code formatting error

## Usage (Future)

```go
// Create gen step
genStep := pipeline.NewGenStep()

// Execute generation
output, result := genStep.Execute(ctx, pipeline.GenInput{
    Module: irModule,
    OutputDir: vfs.MustVPath("/output"),
    Options: pipeline.GenOptions{
        ModulePath: "github.com/example/myapp",
        Workspace:  false,
    },
})
```

## Dependencies

- `github.com/finos/morphir/pkg/models` - Morphir IR types
- `github.com/finos/morphir/pkg/pipeline` - Pipeline infrastructure
- `github.com/finos/morphir/pkg/vfs` - Virtual file system
- `github.com/stretchr/testify` - Testing utilities (removed from final go.mod as it wasn't used yet)

## Next Steps

See [FUTURE_ENHANCEMENTS.md](./FUTURE_ENHANCEMENTS.md) for a detailed roadmap of planned enhancements including:
- Function body generation
- Full sum type support (sealed variant pattern)
- Enhanced type expression mapping
- CLI integration
- BDD feature tests

## Related Documentation

- [Future Enhancements](./FUTURE_ENHANCEMENTS.md) - Detailed enhancement roadmap
- [Golang Backend Requirements](../../../docs/golang-backend-requirements.md)
- [WIT Binding Pipeline](../wit/pipeline/doc.go) - Reference implementation
- [ADR-0003: Toolchain Integration](../../../docs/adr/ADR-0003-toolchain-integration.md) - Toolchain framework architecture
- [WIT Toolchain Adapter](../wit/toolchain/toolchain.go) - Reference toolchain implementation
