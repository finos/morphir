// Package toolchain provides the WIT toolchain adapter for the Morphir toolchain framework.
//
// This package registers WIT as a native toolchain, wrapping the existing WIT pipeline
// steps (make, gen, build) and exposing them through the toolchain abstraction.
package toolchain

import (
	"github.com/finos/morphir/pkg/bindings/wit/pipeline"
	pipelinepkg "github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/toolchain"
)

// WITToolchain returns the WIT toolchain definition for registration.
func WITToolchain() toolchain.Toolchain {
	return toolchain.Toolchain{
		Name:        "wit",
		Description: "WebAssembly Interface Types (WIT) native toolchain",
		Type:        toolchain.ToolchainTypeNative,
		Tasks: []toolchain.TaskDef{
			{
				Name:        "make",
				Description: "Compile WIT source to Morphir IR",
				Handler:     makeMakeHandler(),
				Fulfills:    []string{"make"},
				Outputs: map[string]toolchain.OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
			{
				Name:        "gen",
				Description: "Generate WIT source from Morphir IR",
				Handler:     makeGenHandler(),
				Fulfills:    []string{"gen"},
				Outputs: map[string]toolchain.OutputSpec{
					"wit": {Path: "generated.wit", Type: "wit-source"},
				},
			},
			{
				Name:        "build",
				Description: "Full WIT pipeline: make + gen with round-trip validation",
				Handler:     makeBuildHandler(),
				Fulfills:    []string{"build"},
				Outputs: map[string]toolchain.OutputSpec{
					"ir":  {Path: "module.ir.json", Type: "morphir-ir"},
					"wit": {Path: "generated.wit", Type: "wit-source"},
				},
			},
		},
	}
}

// WITTargets returns the target definitions for WIT operations.
func WITTargets() []toolchain.Target {
	return []toolchain.Target{
		{
			Name:        "make",
			Description: "Compile sources to Morphir IR",
			Produces:    []string{"morphir-ir"},
		},
		{
			Name:        "gen",
			Description: "Generate code from Morphir IR",
			Requires:    []string{"morphir-ir"},
			Produces:    []string{"generated-code"},
		},
		{
			Name:        "build",
			Description: "Full build pipeline (make + gen)",
			Produces:    []string{"morphir-ir", "generated-code"},
		},
	}
}

// Register registers the WIT toolchain and targets with the given registry.
func Register(registry *toolchain.Registry) {
	// Register targets
	for _, target := range WITTargets() {
		registry.RegisterTarget(target)
	}

	// Register toolchain
	registry.Register(WITToolchain())
}

// makeMakeHandler creates the handler for the WIT make task.
func makeMakeHandler() toolchain.NativeTaskHandler {
	return func(ctx pipelinepkg.Context, input toolchain.TaskInput) toolchain.TaskResult {
		// Create the make step
		makeStep := pipeline.NewMakeStep()

		// Build make input from task input
		makeInput := pipeline.MakeInput{
			Options: pipeline.MakeOptions{
				WarningsAsErrors: getBoolOption(input.Options, "warningsAsErrors", false),
				StrictMode:       getBoolOption(input.Options, "strictMode", false),
			},
		}

		// Get source from options
		if source, ok := input.Options["source"].(string); ok {
			makeInput.Source = source
		}

		// Execute the step
		output, stepResult := makeStep.Execute(ctx, makeInput)

		// Convert to toolchain result
		result := toolchain.TaskResult{
			Diagnostics: stepResult.Diagnostics,
			Artifacts:   stepResult.Artifacts,
			Outputs: map[string]any{
				"module":    output.Module,
				"typeCount": len(output.Module.Types()),
			},
		}

		if stepResult.Err != nil {
			result.Error = stepResult.Err
		}

		return result
	}
}

// makeGenHandler creates the handler for the WIT gen task.
func makeGenHandler() toolchain.NativeTaskHandler {
	return func(ctx pipelinepkg.Context, input toolchain.TaskInput) toolchain.TaskResult {
		// Create the gen step
		genStep := pipeline.NewGenStep()

		// Build gen input from task input
		genInput := pipeline.GenInput{
			Options: pipeline.GenOptions{
				WarningsAsErrors: getBoolOption(input.Options, "warningsAsErrors", false),
				Format:           pipeline.DefaultFormatOptions(),
			},
		}

		// Get module from input artifacts
		if module, ok := input.InputArtifacts["module"]; ok {
			// Type assert to the expected module type
			if mod, ok := module.(interface{ Types() any }); ok {
				_ = mod // Module handling would be more sophisticated in practice
			}
		}

		// Execute the step
		output, stepResult := genStep.Execute(ctx, genInput)

		// Convert to toolchain result
		result := toolchain.TaskResult{
			Diagnostics: stepResult.Diagnostics,
			Artifacts:   stepResult.Artifacts,
			Outputs: map[string]any{
				"source":  output.Source,
				"package": output.Package,
			},
		}

		if stepResult.Err != nil {
			result.Error = stepResult.Err
		}

		return result
	}
}

// makeBuildHandler creates the handler for the WIT build task.
func makeBuildHandler() toolchain.NativeTaskHandler {
	return func(ctx pipelinepkg.Context, input toolchain.TaskInput) toolchain.TaskResult {
		// Create the build step
		buildStep := pipeline.NewBuildStep()

		// Build build input from task input
		buildInput := pipeline.BuildInput{
			MakeOptions: pipeline.MakeOptions{
				WarningsAsErrors: getBoolOption(input.Options, "warningsAsErrors", false),
				StrictMode:       getBoolOption(input.Options, "strictMode", false),
			},
			GenOptions: pipeline.GenOptions{
				WarningsAsErrors: getBoolOption(input.Options, "warningsAsErrors", false),
				Format:           pipeline.DefaultFormatOptions(),
			},
		}

		// Get source from options
		if source, ok := input.Options["source"].(string); ok {
			buildInput.Source = source
		}

		// Execute the step
		output, stepResult := buildStep.Execute(ctx, buildInput)

		// Convert to toolchain result
		result := toolchain.TaskResult{
			Diagnostics: stepResult.Diagnostics,
			Artifacts:   stepResult.Artifacts,
			Outputs: map[string]any{
				"module":         output.Make.Module,
				"typeCount":      len(output.Make.Module.Types()),
				"source":         output.Gen.Source,
				"roundTripValid": output.RoundTripValid,
			},
		}

		if stepResult.Err != nil {
			result.Error = stepResult.Err
		}

		return result
	}
}

// getBoolOption extracts a boolean option with a default value.
func getBoolOption(opts map[string]any, key string, defaultVal bool) bool {
	if val, ok := opts[key].(bool); ok {
		return val
	}
	return defaultVal
}
