package pipeline

import (
	"testing"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewBuildStep_ValidatesInput(t *testing.T) {
	step := NewBuildStep()
	ctx := pipeline.NewContext("/tmp", 1, pipeline.ModeDefault, nil)

	t.Run("missing IR path", func(t *testing.T) {
		input := BuildInput{
			IRPath:    vfs.VPath{},
			OutputDir: vfs.MustVPath("/output"),
			Options: BuildOptions{
				GenOptions: GenOptions{
					ModulePath: "github.com/example/test",
				},
			},
		}

		_, result := step.Execute(ctx, input)

		assert.Error(t, result.Err)
		require.NotEmpty(t, result.Diagnostics)
		assert.Equal(t, pipeline.SeverityError, result.Diagnostics[0].Severity)
		assert.Contains(t, result.Diagnostics[0].Message, "IR path is required")
	})

	t.Run("missing output dir", func(t *testing.T) {
		input := BuildInput{
			IRPath:    vfs.MustVPath("/input/morphir-ir.json"),
			OutputDir: vfs.VPath{},
			Options: BuildOptions{
				GenOptions: GenOptions{
					ModulePath: "github.com/example/test",
				},
			},
		}

		_, result := step.Execute(ctx, input)

		assert.Error(t, result.Err)
		require.NotEmpty(t, result.Diagnostics)
		assert.Equal(t, pipeline.SeverityError, result.Diagnostics[0].Severity)
		assert.Contains(t, result.Diagnostics[0].Message, "output directory is required")
	})
}

func TestNewBuildStep_ReturnsStubOutput(t *testing.T) {
	step := NewBuildStep()
	ctx := pipeline.NewContext("/tmp", 1, pipeline.ModeDefault, nil)

	input := BuildInput{
		IRPath:    vfs.MustVPath("/input/morphir-ir.json"),
		OutputDir: vfs.MustVPath("/output"),
		Options: BuildOptions{
			GenOptions: GenOptions{
				ModulePath: "github.com/example/test",
			},
		},
	}

	output, result := step.Execute(ctx, input)

	// Build step is currently a stub, so it should succeed with info diagnostic
	assert.NoError(t, result.Err)
	require.NotEmpty(t, result.Diagnostics)
	assert.Equal(t, pipeline.SeverityInfo, result.Diagnostics[0].Severity)
	assert.Contains(t, result.Diagnostics[0].Message, "placeholder")

	// Output should have initialized maps (accessed through embedded GenOutput)
	assert.NotNil(t, output.GenOutput.GeneratedFiles)
	assert.NotNil(t, output.GenOutput.ModuleFiles)
}
