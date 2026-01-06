package pipeline

import (
	"errors"
	"testing"

	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/require"
)

func TestNewContext(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	require.Equal(t, "/workspace", ctx.WorkspaceRoot)
	require.Equal(t, 3, ctx.FormatVersion)
	require.Equal(t, ModeDefault, ctx.Mode)
	require.NotNil(t, ctx.VFS)
	require.False(t, ctx.Now.IsZero())
}

func TestStepExecution(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step := NewStep("double", "Doubles the input", func(ctx Context, in int) (int, StepResult) {
		return in * 2, StepResult{}
	})

	out, result := step.Execute(ctx, 5)
	require.Equal(t, 10, out)
	require.Empty(t, result.Diagnostics)
	require.Empty(t, result.Artifacts)
	require.NoError(t, result.Err)
}

func TestStepWithDiagnostics(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step := NewStep("validate", "Validates input", func(ctx Context, in int) (int, StepResult) {
		diag := Diagnostic{
			Severity: SeverityWarn,
			Code:     "W001",
			Message:  "Input is small",
			StepName: "validate",
		}
		return in, StepResult{Diagnostics: []Diagnostic{diag}}
	})

	out, result := step.Execute(ctx, 5)
	require.Equal(t, 5, out)
	require.Len(t, result.Diagnostics, 1)
	require.Equal(t, "W001", result.Diagnostics[0].Code)
	require.Equal(t, SeverityWarn, result.Diagnostics[0].Severity)
}

func TestStepWithError(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	expectedErr := errors.New("validation failed")
	step := NewStep("validate", "Validates input", func(ctx Context, in int) (int, StepResult) {
		return 0, StepResult{Err: expectedErr}
	})

	out, result := step.Execute(ctx, 5)
	require.Equal(t, 0, out)
	require.ErrorIs(t, result.Err, expectedErr)
}

func TestSingleStepPipeline(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step := NewStep("increment", "Adds 1 to input", func(ctx Context, in int) (int, StepResult) {
		return in + 1, StepResult{}
	})

	pipeline := NewPipeline("test", "Test pipeline", step)
	out, result, err := pipeline.Run(ctx, 10)

	require.NoError(t, err)
	require.Equal(t, 11, out)
	require.Len(t, result.Steps, 1)
	require.Equal(t, "increment", result.Steps[0].Name)
}

func TestPipelineComposition(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step1 := NewStep("add-five", "Adds 5", func(ctx Context, in int) (int, StepResult) {
		return in + 5, StepResult{}
	})

	step2 := NewStep("double", "Doubles input", func(ctx Context, in int) (int, StepResult) {
		return in * 2, StepResult{}
	})

	step3 := NewStep("subtract-three", "Subtracts 3", func(ctx Context, in int) (int, StepResult) {
		return in - 3, StepResult{}
	})

	// Build pipeline: (10 + 5) * 2 - 3 = 27
	pipeline := NewPipeline("math", "Math operations", step1)
	pipeline = Then(pipeline, step2)
	pipeline = Then(pipeline, step3)

	out, result, err := pipeline.Run(ctx, 10)

	require.NoError(t, err)
	require.Equal(t, 27, out)
	require.Len(t, result.Steps, 3)
	require.Equal(t, "add-five", result.Steps[0].Name)
	require.Equal(t, "double", result.Steps[1].Name)
	require.Equal(t, "subtract-three", result.Steps[2].Name)
}

func TestPipelineTypeTransformation(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	// int -> string
	step1 := NewStep("int-to-string", "Converts int to string", func(ctx Context, in int) (string, StepResult) {
		return "value", StepResult{}
	})

	// string -> bool
	step2 := NewStep("string-to-bool", "Converts string to bool", func(ctx Context, in string) (bool, StepResult) {
		return len(in) > 0, StepResult{}
	})

	pipeline1 := NewPipeline("convert", "Type conversion", step1)
	pipeline2 := Then(pipeline1, step2)

	out, result, err := pipeline2.Run(ctx, 42)

	require.NoError(t, err)
	require.True(t, out)
	require.Len(t, result.Steps, 2)
}

func TestPipelineShortCircuitOnError(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step1 := NewStep("succeed", "Always succeeds", func(ctx Context, in int) (int, StepResult) {
		return in + 1, StepResult{}
	})

	expectedErr := errors.New("step failed")
	step2 := NewStep("fail", "Always fails", func(ctx Context, in int) (int, StepResult) {
		return 0, StepResult{Err: expectedErr}
	})

	step3 := NewStep("never-runs", "Should not run", func(ctx Context, in int) (int, StepResult) {
		require.Fail(t, "This step should not have run")
		return in, StepResult{}
	})

	pipeline := NewPipeline("short-circuit", "Test short-circuiting", step1)
	pipeline = Then(pipeline, step2)
	pipeline = Then(pipeline, step3)

	out, result, err := pipeline.Run(ctx, 10)

	require.Error(t, err)
	require.ErrorIs(t, err, expectedErr)
	require.Equal(t, 0, out)
	require.Len(t, result.Steps, 2) // Only first two steps ran
	require.Equal(t, "succeed", result.Steps[0].Name)
	require.Equal(t, "fail", result.Steps[1].Name)
}

func TestPipelineDiagnosticsAggregation(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step1 := NewStep("warn", "Emits warning", func(ctx Context, in int) (int, StepResult) {
		return in, StepResult{
			Diagnostics: []Diagnostic{
				{Severity: SeverityWarn, Code: "W001", Message: "Warning 1", StepName: "warn"},
			},
		}
	})

	step2 := NewStep("info", "Emits info", func(ctx Context, in int) (int, StepResult) {
		return in, StepResult{
			Diagnostics: []Diagnostic{
				{Severity: SeverityInfo, Code: "I001", Message: "Info 1", StepName: "info"},
				{Severity: SeverityInfo, Code: "I002", Message: "Info 2", StepName: "info"},
			},
		}
	})

	pipeline := NewPipeline("diagnostics", "Test diagnostics", step1)
	pipeline = Then(pipeline, step2)

	out, result, err := pipeline.Run(ctx, 10)

	require.NoError(t, err)
	require.Equal(t, 10, out)
	require.Len(t, result.Diagnostics, 3)
	require.Equal(t, "W001", result.Diagnostics[0].Code)
	require.Equal(t, "I001", result.Diagnostics[1].Code)
	require.Equal(t, "I002", result.Diagnostics[2].Code)
}

func TestPipelineArtifactsAggregation(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step1 := NewStep("gen-report", "Generates report", func(ctx Context, in int) (int, StepResult) {
		return in, StepResult{
			Artifacts: []Artifact{
				{
					Kind:        ArtifactReport,
					Path:        vfs.MustVPath("/report.json"),
					ContentType: "application/json",
					Content:     []byte(`{"value": 1}`),
				},
			},
		}
	})

	step2 := NewStep("gen-metadata", "Generates metadata", func(ctx Context, in int) (int, StepResult) {
		return in, StepResult{
			Artifacts: []Artifact{
				{
					Kind:        ArtifactMetadata,
					Path:        vfs.MustVPath("/meta.json"),
					ContentType: "application/json",
					Content:     []byte(`{"meta": true}`),
				},
			},
		}
	})

	pipeline := NewPipeline("artifacts", "Test artifacts", step1)
	pipeline = Then(pipeline, step2)

	out, result, err := pipeline.Run(ctx, 10)

	require.NoError(t, err)
	require.Equal(t, 10, out)
	require.Len(t, result.Artifacts, 2)
	require.Equal(t, ArtifactReport, result.Artifacts[0].Kind)
	require.Equal(t, ArtifactMetadata, result.Artifacts[1].Kind)
}

func TestStepExecutionTiming(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step := NewStep("timed", "Timed step", func(ctx Context, in int) (int, StepResult) {
		return in, StepResult{}
	})

	pipeline := NewPipeline("timing", "Test timing", step)
	_, result, err := pipeline.Run(ctx, 10)

	require.NoError(t, err)
	require.Len(t, result.Steps, 1)
	require.False(t, result.Steps[0].Started.IsZero())
	require.False(t, result.Steps[0].Finished.IsZero())
	require.True(t, result.Steps[0].Duration >= 0)
	require.True(t, result.Steps[0].Finished.After(result.Steps[0].Started) ||
		result.Steps[0].Finished.Equal(result.Steps[0].Started))
}
