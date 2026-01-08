package pipeline

import (
	"errors"
	"testing"
	"time"

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

// ============================================================================
// Edge Cases and Additional Coverage
// ============================================================================

func TestDiagnosticsPreservedOnError(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step1 := NewStep("warn-first", "Emits warning", func(ctx Context, in int) (int, StepResult) {
		return in, StepResult{
			Diagnostics: []Diagnostic{
				{Severity: SeverityWarn, Code: "W001", Message: "Warning before error"},
			},
		}
	})

	expectedErr := errors.New("step failed after warning")
	step2 := NewStep("fail-with-diag", "Fails with diagnostics", func(ctx Context, in int) (int, StepResult) {
		return 0, StepResult{
			Diagnostics: []Diagnostic{
				{Severity: SeverityError, Code: "E001", Message: "Error diagnostic"},
			},
			Err: expectedErr,
		}
	})

	pipeline := NewPipeline("diag-on-error", "Test diagnostics preserved on error", step1)
	pipeline = Then(pipeline, step2)

	_, result, err := pipeline.Run(ctx, 10)

	require.Error(t, err)
	require.ErrorIs(t, err, expectedErr)
	// Both diagnostics should be preserved even though pipeline errored
	require.Len(t, result.Diagnostics, 2)
	require.Equal(t, "W001", result.Diagnostics[0].Code)
	require.Equal(t, "E001", result.Diagnostics[1].Code)
}

func TestLongPipelineChain(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	// Create a pipeline with 10 steps, each adding 1
	step := NewStep("add-1-step-0", "Adds 1", func(ctx Context, in int) (int, StepResult) {
		return in + 1, StepResult{}
	})
	pipeline := NewPipeline("long-chain", "Test long pipeline", step)

	for i := 1; i < 10; i++ {
		nextStep := NewStep("add-1-step-"+string(rune('0'+i)), "Adds 1", func(ctx Context, in int) (int, StepResult) {
			return in + 1, StepResult{}
		})
		pipeline = Then(pipeline, nextStep)
	}

	out, result, err := pipeline.Run(ctx, 0)

	require.NoError(t, err)
	require.Equal(t, 10, out) // 0 + 10 steps each adding 1
	require.Len(t, result.Steps, 10)
}

func TestContextModes(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})

	modes := []Mode{ModeDefault, ModeInteractive, ModeJSON}

	for _, mode := range modes {
		t.Run(string(mode), func(t *testing.T) {
			ctx := NewContext("/workspace", 3, mode, vfsInstance)
			require.Equal(t, mode, ctx.Mode)

			// Verify context is passed correctly to step
			var receivedMode Mode
			step := NewStep("check-mode", "Checks mode", func(ctx Context, in int) (int, StepResult) {
				receivedMode = ctx.Mode
				return in, StepResult{}
			})

			pipeline := NewPipeline("mode-test", "Test mode", step)
			_, _, err := pipeline.Run(ctx, 0)

			require.NoError(t, err)
			require.Equal(t, mode, receivedMode)
		})
	}
}

func TestDiagnosticWithLocation(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step := NewStep("located-diag", "Emits diagnostic with location", func(ctx Context, in int) (int, StepResult) {
		return in, StepResult{
			Diagnostics: []Diagnostic{
				{
					Severity: SeverityError,
					Code:     "E100",
					Message:  "Error at specific location",
					Location: &Location{
						Path:   vfs.MustVPath("/src/Main.elm"),
						Line:   42,
						Column: 10,
					},
					StepName: "located-diag",
				},
			},
		}
	})

	pipeline := NewPipeline("location-test", "Test location", step)
	_, result, err := pipeline.Run(ctx, 0)

	require.NoError(t, err)
	require.Len(t, result.Diagnostics, 1)
	require.NotNil(t, result.Diagnostics[0].Location)
	require.Equal(t, 42, result.Diagnostics[0].Location.Line)
	require.Equal(t, 10, result.Diagnostics[0].Location.Column)
}

func TestPipelineErrorType(t *testing.T) {
	cause := errors.New("underlying cause")
	pErr := &PipelineError{
		Message:  "step failed",
		Pipeline: "test-pipeline",
		Step:     "failing-step",
		Cause:    cause,
	}

	require.Contains(t, pErr.Error(), "test-pipeline")
	require.Contains(t, pErr.Error(), "failing-step")
	require.Contains(t, pErr.Error(), "step failed")
	require.ErrorIs(t, pErr, cause)
}

func TestPipelineErrorWithoutStep(t *testing.T) {
	pErr := &PipelineError{
		Message:  "pipeline failed",
		Pipeline: "test-pipeline",
		Step:     "",
		Cause:    nil,
	}

	require.Contains(t, pErr.Error(), "test-pipeline")
	require.Contains(t, pErr.Error(), "pipeline failed")
	require.NotContains(t, pErr.Error(), "step")
}

func TestStepResultIndependence(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	// Each step should have independent results
	step1 := NewStep("step-1", "First step", func(ctx Context, in int) (int, StepResult) {
		return in + 1, StepResult{
			Diagnostics: []Diagnostic{{Code: "S1"}},
			Artifacts:   []Artifact{{Kind: ArtifactReport}},
		}
	})

	step2 := NewStep("step-2", "Second step", func(ctx Context, in int) (int, StepResult) {
		return in + 1, StepResult{
			Diagnostics: []Diagnostic{{Code: "S2"}},
			Artifacts:   []Artifact{{Kind: ArtifactMetadata}},
		}
	})

	pipeline := NewPipeline("independence", "Test result independence", step1)
	pipeline = Then(pipeline, step2)

	_, result, err := pipeline.Run(ctx, 0)

	require.NoError(t, err)
	// Verify each step's result is recorded separately
	require.Len(t, result.Steps, 2)
	require.Len(t, result.Steps[0].Result.Diagnostics, 1)
	require.Equal(t, "S1", result.Steps[0].Result.Diagnostics[0].Code)
	require.Len(t, result.Steps[1].Result.Diagnostics, 1)
	require.Equal(t, "S2", result.Steps[1].Result.Diagnostics[0].Code)
}

func TestAllSeverityLevels(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step := NewStep("all-severities", "Emits all severity levels", func(ctx Context, in int) (int, StepResult) {
		return in, StepResult{
			Diagnostics: []Diagnostic{
				{Severity: SeverityInfo, Code: "I001", Message: "Info message"},
				{Severity: SeverityWarn, Code: "W001", Message: "Warning message"},
				{Severity: SeverityError, Code: "E001", Message: "Error message"},
			},
		}
	})

	pipeline := NewPipeline("severities", "Test all severities", step)
	_, result, err := pipeline.Run(ctx, 0)

	require.NoError(t, err)
	require.Len(t, result.Diagnostics, 3)
	require.Equal(t, SeverityInfo, result.Diagnostics[0].Severity)
	require.Equal(t, SeverityWarn, result.Diagnostics[1].Severity)
	require.Equal(t, SeverityError, result.Diagnostics[2].Severity)
}

func TestAllArtifactKinds(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	step := NewStep("all-artifacts", "Produces all artifact kinds", func(ctx Context, in int) (int, StepResult) {
		return in, StepResult{
			Artifacts: []Artifact{
				{Kind: ArtifactIR, Path: vfs.MustVPath("/ir.json")},
				{Kind: ArtifactReport, Path: vfs.MustVPath("/report.json")},
				{Kind: ArtifactCodegen, Path: vfs.MustVPath("/gen/output.go")},
				{Kind: ArtifactMetadata, Path: vfs.MustVPath("/meta.json")},
			},
		}
	})

	pipeline := NewPipeline("artifacts", "Test all artifact kinds", step)
	_, result, err := pipeline.Run(ctx, 0)

	require.NoError(t, err)
	require.Len(t, result.Artifacts, 4)
	require.Equal(t, ArtifactIR, result.Artifacts[0].Kind)
	require.Equal(t, ArtifactReport, result.Artifacts[1].Kind)
	require.Equal(t, ArtifactCodegen, result.Artifacts[2].Kind)
	require.Equal(t, ArtifactMetadata, result.Artifacts[3].Kind)
}

func TestContextTimestamp(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	before := time.Now()
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)
	after := time.Now()

	require.True(t, ctx.Now.After(before) || ctx.Now.Equal(before))
	require.True(t, ctx.Now.Before(after) || ctx.Now.Equal(after))
}

func TestZeroValueInput(t *testing.T) {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	ctx := NewContext("/workspace", 3, ModeDefault, vfsInstance)

	// Test with various zero values
	t.Run("zero int", func(t *testing.T) {
		step := NewStep("identity", "Returns input", func(ctx Context, in int) (int, StepResult) {
			return in, StepResult{}
		})
		pipeline := NewPipeline("zero", "Test zero", step)
		out, _, err := pipeline.Run(ctx, 0)
		require.NoError(t, err)
		require.Equal(t, 0, out)
	})

	t.Run("empty string", func(t *testing.T) {
		step := NewStep("identity", "Returns input", func(ctx Context, in string) (string, StepResult) {
			return in, StepResult{}
		})
		pipeline := NewPipeline("empty", "Test empty", step)
		out, _, err := pipeline.Run(ctx, "")
		require.NoError(t, err)
		require.Equal(t, "", out)
	})

	t.Run("nil slice", func(t *testing.T) {
		step := NewStep("identity", "Returns input", func(ctx Context, in []int) ([]int, StepResult) {
			return in, StepResult{}
		})
		pipeline := NewPipeline("nil", "Test nil", step)
		out, _, err := pipeline.Run(ctx, nil)
		require.NoError(t, err)
		require.Nil(t, out)
	})
}
