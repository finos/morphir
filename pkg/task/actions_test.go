package task

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestDefaultRegistry(t *testing.T) {
	registry := DefaultRegistry()

	// Check all built-in actions are registered
	actions := []string{
		ActionValidate,
		ActionBuild,
		ActionTest,
		ActionClean,
	}

	for _, name := range actions {
		action, ok := registry.Get(name)
		require.True(t, ok, "action %s should be registered", name)
		require.NotNil(t, action, "action %s should not be nil", name)
	}
}

func TestValidateActionFileNotFound(t *testing.T) {
	tmpDir := t.TempDir()
	ctx := newTestContextWithWorkspace(tmpDir)

	output, result := validateAction(ctx, nil)

	require.Error(t, result.Err)
	require.Nil(t, output)
	require.NotEmpty(t, result.Diagnostics)
	require.Equal(t, "VALIDATE_NOT_FOUND", result.Diagnostics[0].Code)
}

func TestValidateActionSuccess(t *testing.T) {
	tmpDir := t.TempDir()

	// Create a valid morphir.ir.json file (matches actual schema format)
	validIR := `{"formatVersion":3,"distribution":["Library",[["morphir"],["example"],["app"]],[],{"modules":[]}]}`
	irPath := filepath.Join(tmpDir, "morphir.ir.json")
	err := os.WriteFile(irPath, []byte(validIR), 0644)
	require.NoError(t, err)

	ctx := newTestContextWithWorkspace(tmpDir)
	output, result := validateAction(ctx, nil)

	require.NoError(t, result.Err)
	require.NotNil(t, output)
	require.NotEmpty(t, result.Diagnostics)
	require.Equal(t, "VALIDATE_OK", result.Diagnostics[0].Code)
}

func TestValidateActionWithCustomPath(t *testing.T) {
	tmpDir := t.TempDir()

	// Create IR in a subdirectory
	subDir := filepath.Join(tmpDir, "output")
	err := os.Mkdir(subDir, 0755)
	require.NoError(t, err)

	validIR := `{"formatVersion":3,"distribution":["Library",[["morphir"],["example"],["app"]],[],{"modules":[]}]}`
	irPath := filepath.Join(subDir, "custom.ir.json")
	err = os.WriteFile(irPath, []byte(validIR), 0644)
	require.NoError(t, err)

	ctx := newTestContextWithWorkspace(tmpDir)
	params := map[string]any{
		"path": "output/custom.ir.json",
	}

	output, result := validateAction(ctx, params)

	require.NoError(t, result.Err)
	require.NotNil(t, output)
}

func TestValidateActionInvalidJSON(t *testing.T) {
	tmpDir := t.TempDir()

	// Create an invalid JSON file
	irPath := filepath.Join(tmpDir, "morphir.ir.json")
	err := os.WriteFile(irPath, []byte("not valid json"), 0644)
	require.NoError(t, err)

	ctx := newTestContextWithWorkspace(tmpDir)
	output, result := validateAction(ctx, nil)

	require.Error(t, result.Err)
	require.NotNil(t, output) // Returns result even on validation error
	require.NotEmpty(t, result.Diagnostics)
}

func TestBuildActionSourceNotFound(t *testing.T) {
	tmpDir := t.TempDir()
	ctx := newTestContextWithWorkspace(tmpDir)

	output, result := buildAction(ctx, nil)

	require.Error(t, result.Err)
	require.Nil(t, output)
	require.NotEmpty(t, result.Diagnostics)
	require.Equal(t, "BUILD_NO_SOURCE", result.Diagnostics[0].Code)
}

func TestBuildActionPlaceholder(t *testing.T) {
	tmpDir := t.TempDir()

	// Create source directory
	srcDir := filepath.Join(tmpDir, "src")
	err := os.Mkdir(srcDir, 0755)
	require.NoError(t, err)

	ctx := newTestContextWithWorkspace(tmpDir)
	output, result := buildAction(ctx, nil)

	require.NoError(t, result.Err)
	require.NotNil(t, output)

	outputMap, ok := output.(map[string]any)
	require.True(t, ok)
	require.Equal(t, "build", outputMap["action"])
	require.Equal(t, "pending", outputMap["status"])

	require.NotEmpty(t, result.Diagnostics)
	require.Equal(t, "BUILD_PENDING", result.Diagnostics[0].Code)
}

func TestBuildActionCustomSource(t *testing.T) {
	tmpDir := t.TempDir()

	// Create custom source directory
	customDir := filepath.Join(tmpDir, "my-source")
	err := os.Mkdir(customDir, 0755)
	require.NoError(t, err)

	ctx := newTestContextWithWorkspace(tmpDir)
	params := map[string]any{
		"source": "my-source",
		"output": "my-output.ir.json",
	}

	output, result := buildAction(ctx, params)

	require.NoError(t, result.Err)
	require.NotNil(t, output)

	outputMap := output.(map[string]any)
	require.Contains(t, outputMap["source"], "my-source")
	require.Contains(t, outputMap["output"], "my-output.ir.json")
}

func TestTestActionPlaceholder(t *testing.T) {
	tmpDir := t.TempDir()
	ctx := newTestContextWithWorkspace(tmpDir)

	output, result := testAction(ctx, nil)

	require.NoError(t, result.Err)
	require.NotNil(t, output)

	outputMap, ok := output.(map[string]any)
	require.True(t, ok)
	require.Equal(t, "test", outputMap["action"])
	require.Equal(t, "pending", outputMap["status"])
	require.Equal(t, "*", outputMap["pattern"])
	require.Equal(t, false, outputMap["verbose"])
}

func TestTestActionWithParams(t *testing.T) {
	tmpDir := t.TempDir()
	ctx := newTestContextWithWorkspace(tmpDir)

	params := map[string]any{
		"pattern": "Test*",
		"verbose": true,
	}

	output, result := testAction(ctx, params)

	require.NoError(t, result.Err)
	outputMap := output.(map[string]any)
	require.Equal(t, "Test*", outputMap["pattern"])
	require.Equal(t, true, outputMap["verbose"])
}

func TestCleanActionRemovesFiles(t *testing.T) {
	tmpDir := t.TempDir()

	// Create files to clean
	irPath := filepath.Join(tmpDir, "morphir.ir.json")
	err := os.WriteFile(irPath, []byte("{}"), 0644)
	require.NoError(t, err)

	morphirDir := filepath.Join(tmpDir, ".morphir")
	err = os.Mkdir(morphirDir, 0755)
	require.NoError(t, err)

	// Create a file inside .morphir/
	cacheFile := filepath.Join(morphirDir, "cache.json")
	err = os.WriteFile(cacheFile, []byte("{}"), 0644)
	require.NoError(t, err)

	ctx := newTestContextWithWorkspace(tmpDir)
	output, result := cleanAction(ctx, nil)

	require.NoError(t, result.Err)
	require.NotNil(t, output)

	outputMap := output.(map[string]any)
	require.Equal(t, "clean", outputMap["action"])
	require.Equal(t, false, outputMap["dry_run"])

	// Verify files are removed
	_, err = os.Stat(irPath)
	require.True(t, os.IsNotExist(err), "morphir.ir.json should be removed")

	_, err = os.Stat(morphirDir)
	require.True(t, os.IsNotExist(err), ".morphir/ should be removed")
}

func TestCleanActionDryRun(t *testing.T) {
	tmpDir := t.TempDir()

	// Create a file to clean
	irPath := filepath.Join(tmpDir, "morphir.ir.json")
	err := os.WriteFile(irPath, []byte("{}"), 0644)
	require.NoError(t, err)

	ctx := newTestContextWithWorkspace(tmpDir)
	params := map[string]any{
		"dry_run": true,
	}

	output, result := cleanAction(ctx, params)

	require.NoError(t, result.Err)
	require.NotNil(t, output)

	outputMap := output.(map[string]any)
	require.Equal(t, true, outputMap["dry_run"])

	// Verify files are NOT removed in dry run
	_, err = os.Stat(irPath)
	require.NoError(t, err, "morphir.ir.json should still exist in dry run")

	// Check diagnostics mention dry run
	foundDryRun := false
	for _, d := range result.Diagnostics {
		if d.Code == "CLEAN_DRY_RUN" {
			foundDryRun = true
			break
		}
	}
	require.True(t, foundDryRun, "should have CLEAN_DRY_RUN diagnostic")
}

func TestCleanActionCustomPatterns(t *testing.T) {
	tmpDir := t.TempDir()

	// Create custom files
	customFile := filepath.Join(tmpDir, "custom-artifact.json")
	err := os.WriteFile(customFile, []byte("{}"), 0644)
	require.NoError(t, err)

	ctx := newTestContextWithWorkspace(tmpDir)
	params := map[string]any{
		"patterns": []any{"custom-artifact.json"},
	}

	output, result := cleanAction(ctx, params)

	require.NoError(t, result.Err)

	outputMap := output.(map[string]any)
	cleaned := outputMap["cleaned"].([]string)
	require.Contains(t, cleaned, "custom-artifact.json")

	// Verify file is removed
	_, err = os.Stat(customFile)
	require.True(t, os.IsNotExist(err))
}

func TestCleanActionMissingFiles(t *testing.T) {
	tmpDir := t.TempDir()
	ctx := newTestContextWithWorkspace(tmpDir)

	// No files exist - should not error
	output, result := cleanAction(ctx, nil)

	require.NoError(t, result.Err)
	require.NotNil(t, output)

	outputMap := output.(map[string]any)
	require.Equal(t, 0, outputMap["count"])
}
