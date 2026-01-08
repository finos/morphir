// Package golang provides Go code generation from Morphir IR.
//
// This package implements a Morphir backend that generates Go modules or
// multi-module workspaces from Morphir IR, following the patterns established
// by the WIT binding.
//
// # Architecture
//
// The golang binding follows the same pipeline architecture as WIT:
//
//   - make: Frontend compilation (future: Go source → Morphir IR)
//   - gen: Backend generation (Morphir IR → Go code)
//   - build: Full pipeline (orchestrates make + gen)
//
// # Code Generation
//
// The gen step converts Morphir IR to Go code:
//
//   - Morphir types → Go types (structs, interfaces, type aliases)
//   - Morphir functions → Go functions
//   - Morphir modules → Go packages
//   - Morphir packages → Go module structure
//
// # Module Layout
//
// The backend supports two output modes:
//
//  1. Single-module: All generated code in one Go module
//  2. Multi-module workspace: Separate Go modules with go.work
//
// For multi-module output, the backend generates:
//
//   - go.work at workspace root with go work use directives
//   - go.mod in each module directory
//   - Package directories preserving Morphir module paths
//
// # Type Mapping
//
// Morphir SDK types map to Go standard library types:
//
//   - Morphir.SDK:Basics:Int → int64
//   - Morphir.SDK:Basics:Float → float64
//   - Morphir.SDK:Basics:Bool → bool
//   - Morphir.SDK:String:String → string
//   - Morphir.SDK:Maybe:Maybe → *T (pointer for optional)
//   - Morphir.SDK:List:List → []T (slice)
//   - Morphir.SDK:Dict:Dict → map[K]V
//   - Morphir.SDK:Result:Result → result type or error pattern
//
// Custom types use the typemap configuration system for overrides.
//
// # Usage
//
// Generate Go code from Morphir IR:
//
//	genStep := pipeline.NewGenStep()
//	output, result := genStep.Execute(ctx, GenInput{
//	    Module: irModule,
//	    OutputDir: vfs.MustVPath("/output"),
//	    Options: GenOptions{
//	        ModulePath: "github.com/example/myapp",
//	        Workspace:  false, // single-module mode
//	    },
//	})
//
// Build step (full pipeline):
//
//	buildStep := pipeline.NewBuildStep()
//	output, result := buildStep.Execute(ctx, BuildInput{
//	    IRPath: vfs.MustVPath("/input/ir.json"),
//	    OutputDir: vfs.MustVPath("/output"),
//	    Options: BuildOptions{
//	        ModulePath: "github.com/example/myapp",
//	    },
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
// # Future Extensions
//
// Planned enhancements:
//
//   - Go frontend (Go → Morphir IR) via go/parser and go/types
//   - Runtime library for Morphir SDK functions
//   - Code formatter integration (gofmt/goimports)
//   - Documentation generation from Morphir docs
//   - Test generation from Morphir specifications
package golang
