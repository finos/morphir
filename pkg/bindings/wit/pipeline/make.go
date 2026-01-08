package pipeline

import (
	"fmt"

	"github.com/finos/morphir/pkg/bindings/wit"
	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// NewMakeStep creates the WIT "make" step (WIT → IR).
// This step compiles WIT source code into Morphir IR.
func NewMakeStep() pipeline.Step[MakeInput, MakeOutput] {
	return pipeline.NewStep[MakeInput, MakeOutput](
		"wit-make",
		"Compiles WIT to Morphir IR",
		func(ctx pipeline.Context, in MakeInput) (MakeOutput, pipeline.StepResult) {
			var result pipeline.StepResult
			var output MakeOutput

			// 1. Parse WIT source
			pkg, err := parseSource(ctx, in)
			if err != nil {
				result.Err = err
				result.Diagnostics = []pipeline.Diagnostic{
					ParseError(err.Error(), "wit-make"),
				}
				return output, result
			}
			output.SourcePackage = pkg

			// 2. Convert to Morphir IR with diagnostic collection
			module, diagnostics := ConvertToIR(pkg, in.Options)
			output.Module = module

			// 3. Handle diagnostics
			result.Diagnostics = diagnostics

			// 4. Check warnings-as-errors
			if in.Options.WarningsAsErrors && HasWarnings(diagnostics) {
				result.Err = fmt.Errorf("warnings treated as errors")
			}

			// 5. Check for errors
			if HasErrors(diagnostics) {
				result.Err = fmt.Errorf("conversion errors occurred")
			}

			return output, result
		},
	)
}

// parseSource parses WIT source from either inline source or file path.
func parseSource(ctx pipeline.Context, in MakeInput) (domain.Package, error) {
	// If source is provided directly, parse it
	if in.Source != "" {
		return wit.ParseWITSource(in.Source)
	}

	// Otherwise, read from VFS
	if in.FilePath.String() == "" {
		return domain.Package{}, fmt.Errorf("either Source or FilePath must be provided")
	}

	// Resolve path from VFS
	entry, _, err := ctx.VFS.Resolve(in.FilePath)
	if err != nil {
		return domain.Package{}, fmt.Errorf("failed to resolve WIT file %s: %w", in.FilePath, err)
	}

	// Ensure it's a file
	file, ok := entry.(vfs.File)
	if !ok {
		return domain.Package{}, fmt.Errorf("path %s is not a file", in.FilePath)
	}

	// Read file contents
	data, err := file.Bytes()
	if err != nil {
		return domain.Package{}, fmt.Errorf("failed to read WIT file: %w", err)
	}

	return wit.ParseWITSource(string(data))
}
