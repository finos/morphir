package pipeline

import (
	"fmt"

	"github.com/finos/morphir/pkg/pipeline"
)

// NewBuildStep creates the Go "build" step (full pipeline).
// This step orchestrates the complete Go code generation pipeline.
func NewBuildStep() pipeline.Step[BuildInput, BuildOutput] {
	return pipeline.NewStep[BuildInput, BuildOutput](
		"golang-build",
		"Full Go pipeline (IR load + gen)",
		func(ctx pipeline.Context, in BuildInput) (BuildOutput, pipeline.StepResult) {
			var result pipeline.StepResult
			var output BuildOutput

			// Validate input
			if in.IRPath.String() == "" {
				result.Diagnostics = []pipeline.Diagnostic{
					DiagnosticError(
						CodeGenerationError,
						"IR path is required",
						"golang-build",
					),
				}
				result.Err = fmt.Errorf("IR path is required")
				return output, result
			}

			if in.OutputDir.String() == "" {
				result.Diagnostics = []pipeline.Diagnostic{
					DiagnosticError(
						CodeGenerationError,
						"output directory is required",
						"golang-build",
					),
				}
				result.Err = fmt.Errorf("output directory is required")
				return output, result
			}

			// Initialize output
			output = BuildOutput{
				GenOutput: GenOutput{
					GeneratedFiles: make(map[string]string),
					ModuleFiles:    []pipeline.Artifact{},
				},
			}

			// Add diagnostic indicating this is a stub implementation
			result.Diagnostics = []pipeline.Diagnostic{
				DiagnosticInfo(
					CodeGenerationError,
					"Go build pipeline is not yet fully implemented - this is a placeholder",
					"golang-build",
				),
			}

			// Future implementation will:
			// 1. Load IR from IRPath using ctx.VFS
			// 2. Parse IR JSON
			// 3. Execute gen step with loaded IR
			// 4. Write generated files to VFS via ctx.VFS
			// 5. Aggregate diagnostics from all steps
			// 6. Create artifacts for all generated files

			return output, result
		},
	)
}
