// Package morphirelm provides the morphir-elm toolchain binding for the Morphir toolchain framework.
//
// This module enables Morphir to orchestrate morphir-elm for IR generation and code generation.
// It registers morphir-elm as an external toolchain that can be invoked via npx.
//
// # Features
//
//   - NPX-based acquisition (no global installation required)
//   - make task: Compiles Elm sources to Morphir IR
//   - gen task: Generates code from Morphir IR (Scala, TypeScript, JsonSchema, etc.)
//   - Configurable version selection
//   - Automatic memory limit configuration for large projects
//
// # Usage
//
// Register the morphir-elm toolchain with a registry:
//
//	import (
//	    "github.com/finos/morphir/pkg/toolchain"
//	    morphirelm "github.com/finos/morphir/pkg/bindings/morphir-elm/toolchain"
//	)
//
//	registry := toolchain.NewRegistry()
//	morphirelm.Register(registry)
//
// Or with a specific version:
//
//	morphirelm.RegisterWithVersion(registry, "2.85.0")
package morphirelm
