// Package toolchain provides the Toolchain Integration Framework for Morphir.
//
// This package implements the core abstractions for orchestrating both external tools
// (like morphir-elm) and native Go implementations (like WIT bindings) through a
// flexible, composable abstraction.
//
// # Core Concepts
//
// **Toolchains**: Tool adapters (native or external) that provide tasks and can hook
// into the execution lifecycle. Toolchains come in two flavors:
//   - Native toolchains: In-process Go implementations (e.g., WIT bindings)
//   - External toolchains: Process-based tools (e.g., morphir-elm via npx)
//
// **Targets**: CLI-facing capabilities (make, gen, test) that tasks fulfill. Targets
// declare artifact contracts (what they produce/require) and support variants
// (e.g., gen:scala, gen:typescript).
//
// **Tasks**: Concrete implementations that produce artifacts (via Go code or process
// execution). Tasks execute through a pipeline: RESOLVE → CACHE → PREPARE → EXECUTE → COLLECT → REPORT.
//
// **Workflows**: Named compositions of targets with staged execution. Workflows define
// explicit stages with parallelism support and conditions for conditional execution.
//
// # Artifact-Based Communication
//
// Tasks produce outputs to `.morphir/out/{toolchain}/{task}/`:
//   - Artifacts are JSONC files (human-readable with comments)
//   - Diagnostics stream as JSONL/NDJSON
//   - Tasks reference other outputs via logical paths (`@toolchain/task:artifact`)
//
// # Example Usage
//
//	// Define a toolchain
//	tc := toolchain.Toolchain{
//	    Name:    "morphir-elm",
//	    Version: "2.90.0",
//	    Acquire: toolchain.AcquireConfig{
//	        Backend: "path",
//	    },
//	    Tasks: []toolchain.TaskDef{
//	        {
//	            Name: "make",
//	            Exec: "morphir-elm",
//	            Args: []string{"make", "-o", "{outputs.ir}"},
//	            Outputs: map[string]toolchain.OutputSpec{
//	                "ir": {Path: "morphir-ir.json", Type: "morphir-ir"},
//	            },
//	            Fulfills: []string{"make"},
//	        },
//	    },
//	}
//
//	// Register and use the toolchain
//	registry := toolchain.NewRegistry()
//	registry.Register(tc)
//
// # Design References
//
// See docs/adr/ADR-0003-toolchain-integration.md and docs/toolchain-integration-design.md
// for complete design documentation.
package toolchain
