# Golang Binding Module

This module provides Go code generation from Morphir IR, following the patterns established by the WIT binding.

## Status

**🚧 Work in Progress - MVP Phase**

This module is currently scaffolded with stub implementations. Full code generation functionality will be implemented in subsequent phases.

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
│   ├── gen.go          # Gen step (stub)
│   └── build.go        # Build step (stub)
├── domain/             # Domain types for Go code generation
│   └── doc.go          # Domain model documentation
└── internal/           # Internal implementation details
    └── doc.go          # Internal package documentation
```

## Pipeline Steps

### Make Step (Not Yet Implemented)

Future: Compiles Go source code to Morphir IR using `go/parser` and `go/types`.

### Gen Step (Stub)

Generates Go code from Morphir IR:
- Types: structs, interfaces, type aliases
- Functions: exported functions with proper signatures
- Modules: Go packages preserving Morphir structure
- Workspaces: Single or multi-module with go.work

### Build Step (Stub)

Orchestrates the full pipeline:
1. Load Morphir IR from file
2. Execute gen step
3. Write generated files to VFS
4. Aggregate diagnostics

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

1. Implement IR → Go domain model adapter
2. Implement Go code emitter
3. Add module/workspace generation
4. Add comprehensive tests
5. Integrate with CLI commands

## Related Documentation

- [Golang Backend Requirements](../../../docs/golang-backend-requirements.md)
- [WIT Binding Pipeline](../wit/pipeline/doc.go) - Reference implementation
