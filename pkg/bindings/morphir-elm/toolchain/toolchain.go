// Package toolchain provides the morphir-elm toolchain adapter for the Morphir toolchain framework.
//
// This package registers morphir-elm as an external toolchain that can be invoked via npx,
// enabling Morphir to orchestrate morphir-elm for IR generation and code generation.
package toolchain

import (
	"time"

	"github.com/finos/morphir/pkg/toolchain"
)

// DefaultVersion is the default morphir-elm version to use.
const DefaultVersion = "2.90.0"

// DefaultTimeout is the default timeout for morphir-elm tasks.
const DefaultTimeout = 10 * time.Minute

// MorphirElmToolchain returns the morphir-elm toolchain definition for registration.
func MorphirElmToolchain() toolchain.Toolchain {
	return MorphirElmToolchainWithVersion(DefaultVersion)
}

// MorphirElmToolchainWithVersion returns the morphir-elm toolchain definition with a specific version.
func MorphirElmToolchainWithVersion(version string) toolchain.Toolchain {
	return toolchain.Toolchain{
		Name:        "morphir-elm",
		Version:     version,
		Description: "Morphir-elm toolchain for Elm-based IR generation and code generation",
		Type:        toolchain.ToolchainTypeExternal,
		Acquire: toolchain.AcquireConfig{
			Backend: "npx",
			Package: "morphir-elm",
			Version: version,
		},
		Timeout: DefaultTimeout,
		Env: map[string]string{
			// Increase Node.js memory limit for large projects
			"NODE_OPTIONS": "--max-old-space-size=4096",
		},
		Tasks: []toolchain.TaskDef{
			makeMakeTask(),
			makeGenTask(),
		},
	}
}

// MorphirElmTargets returns the target definitions for morphir-elm operations.
func MorphirElmTargets() []toolchain.Target {
	return []toolchain.Target{
		{
			Name:        "make",
			Description: "Compile Elm sources to Morphir IR",
			Produces:    []string{"morphir-ir"},
		},
		{
			Name:        "gen",
			Description: "Generate code from Morphir IR",
			Requires:    []string{"morphir-ir"},
			Produces:    []string{"generated-code"},
			Variants:    []string{"Scala", "JsonSchema", "TypeScript", "Snowpark", "Spark"},
		},
	}
}

// Register registers the morphir-elm toolchain and targets with the given registry.
func Register(registry *toolchain.Registry) {
	RegisterWithVersion(registry, DefaultVersion)
}

// RegisterWithVersion registers the morphir-elm toolchain with a specific version.
func RegisterWithVersion(registry *toolchain.Registry, version string) {
	// Register targets
	for _, target := range MorphirElmTargets() {
		registry.RegisterTarget(target)
	}

	// Register toolchain
	registry.Register(MorphirElmToolchainWithVersion(version))
}

// makeMakeTask creates the make task definition.
// The make task compiles Elm source code to Morphir IR.
func makeMakeTask() toolchain.TaskDef {
	return toolchain.TaskDef{
		Name:        "make",
		Description: "Compile Elm sources to Morphir IR",
		Args:        []string{"make", "-o", "{outputs.ir}"},
		Inputs: toolchain.InputSpec{
			Files: []string{
				"elm.json",
				"src/**/*.elm",
				"morphir.json",
			},
		},
		Outputs: map[string]toolchain.OutputSpec{
			"ir": {
				Path: "morphir-ir.json",
				Type: "morphir-ir",
			},
		},
		Fulfills: []string{"make"},
		Timeout:  DefaultTimeout,
	}
}

// makeGenTask creates the gen task definition.
// The gen task generates code from Morphir IR in various target languages.
func makeGenTask() toolchain.TaskDef {
	return toolchain.TaskDef{
		Name:        "gen",
		Description: "Generate code from Morphir IR",
		Args: []string{
			"gen",
			"-i", "{inputs.ir}",
			"-o", "{outputs.dir}",
			"-t", "{variant}",
		},
		Inputs: toolchain.InputSpec{
			// Reference the IR output from the make task
			Artifacts: map[string]string{
				"ir": "@morphir-elm/make:ir",
			},
		},
		Outputs: map[string]toolchain.OutputSpec{
			"dir": {
				Path: "dist/{variant}",
				Type: "generated-code",
			},
		},
		Fulfills: []string{"gen"},
		Variants: []string{
			"Scala",
			"JsonSchema",
			"TypeScript",
			"Snowpark",
			"Spark",
		},
		Timeout: DefaultTimeout,
	}
}

// ValidateMakeOptions validates the options for the make task.
func ValidateMakeOptions(opts map[string]any) error {
	// Make task has no required options - it uses file inputs from elm.json
	return nil
}

// ValidateGenOptions validates the options for the gen task.
func ValidateGenOptions(opts map[string]any) error {
	// Gen task requires variant to be specified
	// This is handled by the toolchain framework's variant validation
	return nil
}
