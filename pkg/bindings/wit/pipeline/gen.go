package pipeline

import (
	"fmt"

	"github.com/finos/morphir/pkg/bindings/wit"
	"github.com/finos/morphir/pkg/pipeline"
)

// NewGenStep creates the WIT "gen" step (IR → WIT).
// This step generates WIT source code from Morphir IR.
func NewGenStep() pipeline.Step[GenInput, GenOutput] {
	return pipeline.NewStep[GenInput, GenOutput](
		"wit-gen",
		"Generates WIT from Morphir IR",
		func(ctx pipeline.Context, in GenInput) (GenOutput, pipeline.StepResult) {
			var result pipeline.StepResult
			var output GenOutput

			// 1. Convert IR to WIT domain model
			pkg, diagnostics := ConvertFromIR(in.Module, in.Options)
			output.Package = pkg

			// 2. Handle diagnostics
			result.Diagnostics = diagnostics

			// 3. Check warnings-as-errors
			if in.Options.WarningsAsErrors && HasWarnings(diagnostics) {
				result.Err = fmt.Errorf("warnings treated as errors")
			}

			// 4. Check for errors
			if HasErrors(diagnostics) {
				result.Err = fmt.Errorf("generation errors occurred")
			}

			// 5. If no errors, emit WIT source
			if result.Err == nil {
				output.Source = wit.EmitPackage(pkg)

				// 6. Create artifact if output path specified
				if in.OutputPath.String() != "" {
					result.Artifacts = []pipeline.Artifact{{
						Kind:        pipeline.ArtifactCodegen,
						Path:        in.OutputPath,
						ContentType: "text/plain",
						Content:     []byte(output.Source),
					}}
				}
			}

			return output, result
		},
	)
}
