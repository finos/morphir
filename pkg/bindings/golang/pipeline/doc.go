// Package pipeline provides Go code generation pipeline adapters for Morphir processing.
//
// This package implements pipeline steps that integrate Go code generation
// with Morphir's processing infrastructure, following morphir-elm's established
// patterns and the WIT binding implementation:
//
//   - make: Frontend compilation (future: Go → Morphir IR)
//   - gen: Backend generation (Morphir IR → Go code)
//   - build: Full pipeline (IR → Go module/workspace)
//
// # Architecture
//
// The pipeline steps follow the [pipeline.Step] interface pattern:
//
//	Step[In, Out] with func(Context, In) (Out, StepResult)
//
// Each step produces diagnostics for warnings and errors, supporting both
// lossy transformation warnings and strict validation modes.
//
// # Module Generation
//
// The gen step generates Go modules from Morphir IR with two output modes:
//
//  1. Single-module: All packages in one go.mod
//  2. Multi-module workspace: Multiple go.mod files with go.work
//
// Generated structure:
//
//	output/
//	├── go.mod (or go.work for multi-module)
//	├── package1/
//	│   ├── go.mod (multi-module only)
//	│   ├── types.go
//	│   └── functions.go
//	└── package2/
//	    ├── go.mod (multi-module only)
//	    └── types.go
//
// # Type Mapping
//
// Morphir IR types are mapped to Go types following language conventions:
//
//   - Record types → structs with exported fields
//   - Variant types → sealed interfaces with type switch
//   - Type aliases → Go type aliases
//   - Functions → exported functions
//   - Constructors → constructor functions (NewT pattern)
//
// The typemap package provides configurable overrides for SDK types.
//
// # Usage
//
// Gen step (IR → Go):
//
//	genStep := pipeline.NewGenStep()
//	output, result := genStep.Execute(ctx, GenInput{
//	    Module: irModule,
//	    OutputDir: vfs.MustVPath("/output"),
//	    Options: GenOptions{
//	        ModulePath: "github.com/example/myapp",
//	        Workspace:  false,
//	    },
//	})
//
// Build step (full pipeline):
//
//	buildStep := pipeline.NewBuildStep()
//	output, result := buildStep.Execute(ctx, BuildInput{
//	    IRPath: vfs.MustVPath("/input/ir.json"),
//	    OutputDir: vfs.MustVPath("/output"),
//	})
//
// # Diagnostics
//
// The pipeline emits structured diagnostics with codes:
//
//   - GO001: Type mapping information lost
//   - GO002: Unsupported IR construct
//   - GO003: Name collision in generated code
//   - GO004: Invalid Go identifier generated
//   - GO005: Module structure conflict
//
// # Future Extensibility
//
// The design supports future enhancements:
//
//   - Go frontend via go/parser and go/types
//   - Attributes for preserving Go-specific metadata in IR
//   - Decorators for Go constraints (build tags, etc.)
//   - Per-diagnostic severity configuration
//   - Integration with go fmt/goimports
package pipeline
