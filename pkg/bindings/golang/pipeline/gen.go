package pipeline

import (
	"fmt"

	"github.com/finos/morphir/pkg/pipeline"
)

// NewGenStep creates the Go "gen" step (Morphir IR → Go code).
// This step generates Go source code from Morphir IR.
func NewGenStep() pipeline.Step[GenInput, GenOutput] {
	return pipeline.NewStep[GenInput, GenOutput](
		"golang-gen",
		"Generates Go code from Morphir IR",
		func(ctx pipeline.Context, in GenInput) (GenOutput, pipeline.StepResult) {
			var result pipeline.StepResult
			var output GenOutput

			// Validate input
			if in.OutputDir.String() == "" {
				result.Diagnostics = []pipeline.Diagnostic{
					DiagnosticError(
						CodeGenerationError,
						"output directory is required",
						"golang-gen",
					),
				}
				result.Err = fmt.Errorf("output directory is required")
				return output, result
			}

			if in.Options.ModulePath == "" {
				result.Diagnostics = []pipeline.Diagnostic{
					DiagnosticError(
						CodeGenerationError,
						"module path is required",
						"golang-gen",
					),
				}
				result.Err = fmt.Errorf("module path is required")
				return output, result
			}

			// Initialize output
			output = GenOutput{
				GeneratedFiles: make(map[string]string),
				ModuleFiles:    []pipeline.Artifact{},
			}

			// Add diagnostic indicating this is a stub implementation
			result.Diagnostics = []pipeline.Diagnostic{
				DiagnosticInfo(
					CodeGenerationError,
					"Go code generation is not yet fully implemented - this is a placeholder",
					"golang-gen",
				),
			}

			// Future implementation will:
			// 1. Convert Morphir IR to Go domain model
			// 2. Generate Go source code from domain model
			// 3. Create go.mod file(s)
			// 4. Create go.work file if workspace mode
			// 5. Add artifacts to result

			return output, result
		},
	)
}
