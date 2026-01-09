// Package toolchain provides the Go toolchain adapter for the Morphir toolchain framework.
//
// This package registers Go as a native toolchain, wrapping the existing Go pipeline
// steps (make, gen, build) and exposing them through the toolchain abstraction.
package toolchain

import (
	"fmt"

	"github.com/finos/morphir/pkg/bindings/golang/pipeline"
	"github.com/finos/morphir/pkg/models/ir"
	pipelinepkg "github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/toolchain"
	"github.com/finos/morphir/pkg/vfs"
)

// GolangToolchain returns the Go toolchain definition for registration.
func GolangToolchain() toolchain.Toolchain {
	return toolchain.Toolchain{
		Name:        "golang",
		Description: "Go language native toolchain for Morphir IR",
		Type:        toolchain.ToolchainTypeNative,
		Tasks: []toolchain.TaskDef{
			{
				Name:        "make",
				Description: "Compile Go source to Morphir IR (not yet implemented)",
				Handler:     makeMakeHandler(),
				Fulfills:    []string{"make"},
				Outputs: map[string]toolchain.OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
			{
				Name:        "gen",
				Description: "Generate Go source code from Morphir IR",
				Handler:     makeGenHandler(),
				Fulfills:    []string{"gen"},
				Outputs: map[string]toolchain.OutputSpec{
					"source":  {Path: "generated/", Type: "go-source"},
					"go.mod":  {Path: "go.mod", Type: "go-module"},
					"go.work": {Path: "go.work", Type: "go-workspace"},
				},
			},
			{
				Name:        "build",
				Description: "Full Go pipeline: load IR + gen",
				Handler:     makeBuildHandler(),
				Fulfills:    []string{"build"},
				Outputs: map[string]toolchain.OutputSpec{
					"source":  {Path: "generated/", Type: "go-source"},
					"go.mod":  {Path: "go.mod", Type: "go-module"},
					"go.work": {Path: "go.work", Type: "go-workspace"},
				},
			},
		},
	}
}

// GolangTargets returns the target definitions for Go operations.
func GolangTargets() []toolchain.Target {
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
			Variants:    []string{"golang"},
		},
		{
			Name:        "build",
			Description: "Full build pipeline (make + gen)",
			Produces:    []string{"morphir-ir", "generated-code"},
		},
	}
}

// Register registers the Go toolchain and targets with the given registry.
func Register(registry *toolchain.Registry) {
	// Register targets
	for _, target := range GolangTargets() {
		registry.RegisterTarget(target)
	}

	// Register toolchain
	registry.Register(GolangToolchain())
}

// makeMakeHandler creates the handler for the Go make task.
// Note: The Go frontend (Go -> Morphir IR) is not yet implemented.
func makeMakeHandler() toolchain.NativeTaskHandler {
	return func(ctx pipelinepkg.Context, input toolchain.TaskInput) toolchain.TaskResult {
		// Create the make step
		makeStep := pipeline.NewMakeStep()

		// Collect any diagnostics from option parsing
		var optionDiagnostics []pipelinepkg.Diagnostic

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

		// Get file path from options
		if filePath, ok := input.Options["filePath"].(string); ok {
			vpath, err := vfs.ParseVPath(filePath)
			if err != nil {
				optionDiagnostics = append(optionDiagnostics, pipeline.DiagnosticWarn(
					pipeline.CodeInvalidPath,
					fmt.Sprintf("invalid filePath %q: %v", filePath, err),
					"golang-make",
				))
			} else {
				makeInput.FilePath = vpath
			}
		}

		// Execute the step
		output, stepResult := makeStep.Execute(ctx, makeInput)

		// Convert to toolchain result, prepending option diagnostics
		allDiagnostics := append(optionDiagnostics, stepResult.Diagnostics...)
		result := toolchain.TaskResult{
			Diagnostics: allDiagnostics,
			Artifacts:   stepResult.Artifacts,
			Outputs: map[string]any{
				"module": output.Module,
			},
		}

		if stepResult.Err != nil {
			result.Error = stepResult.Err
		}

		return result
	}
}

// makeGenHandler creates the handler for the Go gen task.
func makeGenHandler() toolchain.NativeTaskHandler {
	return func(ctx pipelinepkg.Context, input toolchain.TaskInput) toolchain.TaskResult {
		// Create the gen step
		genStep := pipeline.NewGenStep()

		// Collect any diagnostics from option parsing
		var optionDiagnostics []pipelinepkg.Diagnostic

		// Build gen input from task input
		genInput := pipeline.GenInput{
			Options: pipeline.GenOptions{
				ModulePath:       getStringOption(input.Options, "modulePath", ""),
				Workspace:        getBoolOption(input.Options, "workspace", false),
				WarningsAsErrors: getBoolOption(input.Options, "warningsAsErrors", false),
				Format:           pipeline.DefaultFormatOptions(),
			},
		}

		// Get output directory from options
		if outputDir, ok := input.Options["outputDir"].(string); ok {
			vpath, err := vfs.ParseVPath(outputDir)
			if err != nil {
				optionDiagnostics = append(optionDiagnostics, pipeline.DiagnosticWarn(
					pipeline.CodeInvalidPath,
					fmt.Sprintf("invalid outputDir %q: %v", outputDir, err),
					"golang-gen",
				))
			} else {
				genInput.OutputDir = vpath
			}
		}

		// Get module from input artifacts
		if module, ok := input.InputArtifacts["module"]; ok {
			if mod, ok := module.(ir.ModuleDefinition[any, any]); ok {
				genInput.Module = mod
			}
		}

		// Also check options for module (alternative input method)
		if module, ok := input.Options["module"]; ok {
			if mod, ok := module.(ir.ModuleDefinition[any, any]); ok {
				genInput.Module = mod
			}
		}

		// Execute the step
		output, stepResult := genStep.Execute(ctx, genInput)

		// Build outputs map
		outputs := map[string]any{
			"generatedFiles": output.GeneratedFiles,
			"fileCount":      len(output.GeneratedFiles),
		}

		// Add module files info
		if len(output.ModuleFiles) > 0 {
			outputs["moduleFiles"] = output.ModuleFiles
		}

		// Add workspace file info
		if output.WorkspaceFile != nil {
			outputs["workspaceFile"] = output.WorkspaceFile
		}

		// Convert to toolchain result, prepending option diagnostics
		allDiagnostics := append(optionDiagnostics, stepResult.Diagnostics...)
		result := toolchain.TaskResult{
			Diagnostics: allDiagnostics,
			Artifacts:   stepResult.Artifacts,
			Outputs:     outputs,
		}

		if stepResult.Err != nil {
			result.Error = stepResult.Err
		}

		return result
	}
}

// makeBuildHandler creates the handler for the Go build task.
func makeBuildHandler() toolchain.NativeTaskHandler {
	return func(ctx pipelinepkg.Context, input toolchain.TaskInput) toolchain.TaskResult {
		// Create the build step
		buildStep := pipeline.NewBuildStep()

		// Collect any diagnostics from option parsing
		var optionDiagnostics []pipelinepkg.Diagnostic

		// Build build input from task input
		buildInput := pipeline.BuildInput{
			Options: pipeline.BuildOptions{
				MakeOptions: pipeline.MakeOptions{
					WarningsAsErrors: getBoolOption(input.Options, "warningsAsErrors", false),
					StrictMode:       getBoolOption(input.Options, "strictMode", false),
				},
				GenOptions: pipeline.GenOptions{
					ModulePath:       getStringOption(input.Options, "modulePath", ""),
					Workspace:        getBoolOption(input.Options, "workspace", false),
					WarningsAsErrors: getBoolOption(input.Options, "warningsAsErrors", false),
					Format:           pipeline.DefaultFormatOptions(),
				},
			},
		}

		// Get IR path from options
		if irPath, ok := input.Options["irPath"].(string); ok {
			vpath, err := vfs.ParseVPath(irPath)
			if err != nil {
				optionDiagnostics = append(optionDiagnostics, pipeline.DiagnosticWarn(
					pipeline.CodeInvalidPath,
					fmt.Sprintf("invalid irPath %q: %v", irPath, err),
					"golang-build",
				))
			} else {
				buildInput.IRPath = vpath
			}
		}

		// Get output directory from options
		if outputDir, ok := input.Options["outputDir"].(string); ok {
			vpath, err := vfs.ParseVPath(outputDir)
			if err != nil {
				optionDiagnostics = append(optionDiagnostics, pipeline.DiagnosticWarn(
					pipeline.CodeInvalidPath,
					fmt.Sprintf("invalid outputDir %q: %v", outputDir, err),
					"golang-build",
				))
			} else {
				buildInput.OutputDir = vpath
			}
		}

		// Execute the step
		output, stepResult := buildStep.Execute(ctx, buildInput)

		// Build outputs map
		outputs := map[string]any{
			"generatedFiles": output.GenOutput.GeneratedFiles,
			"fileCount":      len(output.GenOutput.GeneratedFiles),
		}

		// Add module files info
		if len(output.GenOutput.ModuleFiles) > 0 {
			outputs["moduleFiles"] = output.GenOutput.ModuleFiles
		}

		// Add workspace file info
		if output.GenOutput.WorkspaceFile != nil {
			outputs["workspaceFile"] = output.GenOutput.WorkspaceFile
		}

		// Convert to toolchain result, prepending option diagnostics
		allDiagnostics := append(optionDiagnostics, stepResult.Diagnostics...)
		result := toolchain.TaskResult{
			Diagnostics: allDiagnostics,
			Artifacts:   stepResult.Artifacts,
			Outputs:     outputs,
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

// getStringOption extracts a string option with a default value.
func getStringOption(opts map[string]any, key string, defaultVal string) string {
	if val, ok := opts[key].(string); ok {
		return val
	}
	return defaultVal
}

// getIntOption extracts an integer option with a default value.
func getIntOption(opts map[string]any, key string, defaultVal int) int {
	if val, ok := opts[key].(int); ok {
		return val
	}
	// Also try float64 (common in JSON unmarshaling)
	if val, ok := opts[key].(float64); ok {
		return int(val)
	}
	return defaultVal
}

// ValidateGenOptions validates the options for the gen task.
func ValidateGenOptions(opts map[string]any) error {
	modulePath := getStringOption(opts, "modulePath", "")
	if modulePath == "" {
		return fmt.Errorf("modulePath option is required for gen task")
	}
	return nil
}
