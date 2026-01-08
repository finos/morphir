package pipeline

import (
	"testing"

	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/require"
)

// createTestVFS creates an in-memory VFS with the given file content at the given path.
func createTestVFS(t *testing.T, filePath string, content []byte) vfs.VFS {
	t.Helper()

	// Create an empty root folder
	root := vfs.NewMemFolder(vfs.MustVPath("/"), vfs.Meta{}, vfs.Origin{MountName: "workspace"}, nil)

	// Create a mount with the root
	mount := vfs.Mount{
		Name: "workspace",
		Mode: vfs.MountRW,
		Root: root,
	}

	// Create overlay VFS
	overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})

	// Get writer and create the file
	writer, err := overlay.Writer()
	require.NoError(t, err)

	_, err = writer.CreateFile(vfs.MustVPath(filePath), content, vfs.WriteOptions{MkdirParents: true})
	require.NoError(t, err)

	return overlay
}

// createEmptyTestVFS creates an empty in-memory VFS.
func createEmptyTestVFS() vfs.VFS {
	root := vfs.NewMemFolder(vfs.MustVPath("/"), vfs.Meta{}, vfs.Origin{MountName: "workspace"}, nil)
	mount := vfs.Mount{
		Name: "workspace",
		Mode: vfs.MountRW,
		Root: root,
	}
	return vfs.NewOverlayVFS([]vfs.Mount{mount})
}

func TestValidateStepSuccess(t *testing.T) {
	// Create in-memory VFS with valid IR
	validIR := []byte(`{"formatVersion": 3, "distribution": []}`)
	overlay := createTestVFS(t, "/morphir.ir.json", validIR)
	ctx := NewContext("/workspace", 3, ModeDefault, overlay)

	step := NewValidateStep()
	input := ValidateInput{
		IRPath:  vfs.MustVPath("/morphir.ir.json"),
		Version: 0, // Auto-detect
	}

	output, result := step.Execute(ctx, input)

	require.NoError(t, result.Err)
	require.True(t, output.Valid)
	require.Equal(t, 3, output.Version)
	require.Empty(t, output.Errors)
	require.Len(t, result.Artifacts, 1)
	require.Equal(t, ArtifactReport, result.Artifacts[0].Kind)
}

func TestValidateStepInvalidJSON(t *testing.T) {
	// Create in-memory VFS with invalid JSON
	invalidJSON := []byte(`{invalid json`)
	overlay := createTestVFS(t, "/morphir.ir.json", invalidJSON)
	ctx := NewContext("/workspace", 3, ModeDefault, overlay)

	step := NewValidateStep()
	input := ValidateInput{
		IRPath:  vfs.MustVPath("/morphir.ir.json"),
		Version: 0,
	}

	output, result := step.Execute(ctx, input)

	require.NoError(t, result.Err) // No error returned, but validation fails
	require.False(t, output.Valid)
	require.NotEmpty(t, output.Errors)
	require.Len(t, result.Diagnostics, 1)
	require.Equal(t, SeverityError, result.Diagnostics[0].Severity)
}

func TestValidateStepInvalidVersion(t *testing.T) {
	// Create in-memory VFS with invalid format version
	invalidVersion := []byte(`{"formatVersion": 99}`)
	overlay := createTestVFS(t, "/morphir.ir.json", invalidVersion)
	ctx := NewContext("/workspace", 3, ModeDefault, overlay)

	step := NewValidateStep()
	input := ValidateInput{
		IRPath:  vfs.MustVPath("/morphir.ir.json"),
		Version: 0,
	}

	output, result := step.Execute(ctx, input)

	require.NoError(t, result.Err)
	require.False(t, output.Valid)
	require.Contains(t, output.Errors[0], "invalid formatVersion")
}

func TestValidateStepFileNotFound(t *testing.T) {
	overlay := createEmptyTestVFS()
	ctx := NewContext("/workspace", 3, ModeDefault, overlay)

	step := NewValidateStep()
	input := ValidateInput{
		IRPath:  vfs.MustVPath("/nonexistent.json"),
		Version: 0,
	}

	_, result := step.Execute(ctx, input)

	require.Error(t, result.Err)
	require.Contains(t, result.Err.Error(), "failed to resolve")
	require.Len(t, result.Diagnostics, 1)
	require.Equal(t, "VALIDATE_RESOLVE_ERROR", result.Diagnostics[0].Code)
}

func TestValidateStepWithPipeline(t *testing.T) {
	// Test the validation step works correctly in a pipeline
	validIR := []byte(`{"formatVersion": 3, "distribution": []}`)
	overlay := createTestVFS(t, "/morphir.ir.json", validIR)
	ctx := NewContext("/workspace", 3, ModeDefault, overlay)

	validateStep := NewValidateStep()
	pipeline := NewPipeline("validate-ir", "Validates Morphir IR", validateStep)

	input := ValidateInput{
		IRPath:  vfs.MustVPath("/morphir.ir.json"),
		Version: 0,
	}

	output, pipelineResult, err := pipeline.Run(ctx, input)

	require.NoError(t, err)
	require.True(t, output.Valid)
	require.Len(t, pipelineResult.Steps, 1)
	require.Equal(t, "validate", pipelineResult.Steps[0].Name)
	require.Len(t, pipelineResult.Artifacts, 1)
}

func TestValidateStepExplicitVersion(t *testing.T) {
	// Test with explicit version specified
	validIR := []byte(`{"formatVersion": 3, "distribution": []}`)
	overlay := createTestVFS(t, "/morphir.ir.json", validIR)
	ctx := NewContext("/workspace", 3, ModeDefault, overlay)

	step := NewValidateStep()
	input := ValidateInput{
		IRPath:  vfs.MustVPath("/morphir.ir.json"),
		Version: 3, // Explicit version
	}

	output, result := step.Execute(ctx, input)

	require.NoError(t, result.Err)
	require.True(t, output.Valid)
	require.Equal(t, 3, output.Version)
}

func TestValidateStepCustomValidator(t *testing.T) {
	// Test with custom validation function
	originalFn := validateIRBytes
	defer func() { validateIRBytes = originalFn }()

	// Set custom validator that always fails
	SetValidateIRBytes(func(data []byte, sourcePath string, version int) (*internalValidationResult, error) {
		return &internalValidationResult{
			Valid:   false,
			Version: 3,
			Path:    sourcePath,
			Errors:  []string{"custom validation error"},
		}, nil
	})

	validIR := []byte(`{"formatVersion": 3}`)
	overlay := createTestVFS(t, "/morphir.ir.json", validIR)
	ctx := NewContext("/workspace", 3, ModeDefault, overlay)

	step := NewValidateStep()
	input := ValidateInput{
		IRPath:  vfs.MustVPath("/morphir.ir.json"),
		Version: 0,
	}

	output, result := step.Execute(ctx, input)

	require.NoError(t, result.Err)
	require.False(t, output.Valid)
	require.Contains(t, output.Errors[0], "custom validation error")
	require.Len(t, result.Diagnostics, 1)
}
