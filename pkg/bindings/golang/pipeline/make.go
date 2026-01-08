package pipeline

import (
	"github.com/finos/morphir/pkg/pipeline"
)

// NewMakeStep creates the Go "make" step (Go source → Morphir IR).
// This is a placeholder for future functionality when Go frontend is implemented.
func NewMakeStep() pipeline.Step[MakeInput, MakeOutput] {
	return pipeline.NewStep[MakeInput, MakeOutput](
		"golang-make",
		"Compiles Go source to Morphir IR (not yet implemented)",
		func(ctx pipeline.Context, in MakeInput) (MakeOutput, pipeline.StepResult) {
			var result pipeline.StepResult
			var output MakeOutput

			// Add diagnostic indicating this is not yet implemented
			result.Diagnostics = []pipeline.Diagnostic{
				DiagnosticWarn(
					CodeUnsupportedConstruct,
					"Go frontend (Go → Morphir IR) is not yet implemented",
					"golang-make",
				),
			}

			return output, result
		},
	)
}
