package pipeline

import (
	"testing"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewMakeStep_ReturnsNotImplementedWarning(t *testing.T) {
	step := NewMakeStep()
	ctx := pipeline.NewContext("/tmp", 1, pipeline.ModeDefault, nil)

	input := MakeInput{
		FilePath: vfs.MustVPath("/src/main.go"),
		Options:  MakeOptions{},
	}

	_, result := step.Execute(ctx, input)

	// Make step is not implemented, so it should return a warning
	assert.NoError(t, result.Err)
	require.NotEmpty(t, result.Diagnostics)
	assert.Equal(t, pipeline.SeverityWarn, result.Diagnostics[0].Severity)
	assert.Contains(t, result.Diagnostics[0].Message, "not yet implemented")
}

func TestNewMakeStep_EmptyInput(t *testing.T) {
	step := NewMakeStep()
	ctx := pipeline.NewContext("/tmp", 1, pipeline.ModeDefault, nil)

	input := MakeInput{}

	_, result := step.Execute(ctx, input)

	// Should still return warning even with empty input
	assert.NoError(t, result.Err)
	require.NotEmpty(t, result.Diagnostics)
	assert.Equal(t, pipeline.SeverityWarn, result.Diagnostics[0].Severity)
}

func TestNewMakeStep_WithWarningsAsErrors(t *testing.T) {
	step := NewMakeStep()
	ctx := pipeline.NewContext("/tmp", 1, pipeline.ModeDefault, nil)

	input := MakeInput{
		FilePath: vfs.MustVPath("/src/main.go"),
		Options: MakeOptions{
			WarningsAsErrors: true,
		},
	}

	_, result := step.Execute(ctx, input)

	// Make step always produces a warning about not being implemented
	// This test documents that behavior
	assert.NoError(t, result.Err)
	require.NotEmpty(t, result.Diagnostics)
}
