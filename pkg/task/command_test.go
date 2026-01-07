package task

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/require"
)

func TestCommandRunnerSimpleCommand(t *testing.T) {
	runner := &CommandRunner{}

	// Use a simple cross-platform command
	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "echo", "hello"}
	} else {
		cmd = []string{"echo", "hello"}
	}

	output, err := runner.Run(cmd, nil)

	require.NoError(t, err)
	require.Equal(t, 0, output.ExitCode)
	require.Contains(t, output.Stdout, "hello")
}

func TestCommandRunnerWithEnv(t *testing.T) {
	runner := &CommandRunner{}

	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "echo", "%TEST_VAR%"}
	} else {
		cmd = []string{"sh", "-c", "echo $TEST_VAR"}
	}

	env := map[string]string{
		"TEST_VAR": "test_value",
	}

	output, err := runner.Run(cmd, env)

	require.NoError(t, err)
	require.Equal(t, 0, output.ExitCode)
	require.Contains(t, output.Stdout, "test_value")
}

func TestCommandRunnerJSONOutput(t *testing.T) {
	runner := &CommandRunner{}

	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "echo", `{"key":"value"}`}
	} else {
		cmd = []string{"echo", `{"key":"value"}`}
	}

	output, err := runner.Run(cmd, nil)

	require.NoError(t, err)
	require.Equal(t, 0, output.ExitCode)
	require.NotNil(t, output.Parsed)

	parsed, ok := output.Parsed.(map[string]any)
	require.True(t, ok)
	require.Equal(t, "value", parsed["key"])
}

func TestCommandRunnerFailedCommand(t *testing.T) {
	runner := &CommandRunner{}

	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "exit", "1"}
	} else {
		cmd = []string{"sh", "-c", "exit 1"}
	}

	output, err := runner.Run(cmd, nil)

	require.NoError(t, err) // Run doesn't return error for non-zero exit
	require.Equal(t, 1, output.ExitCode)
}

func TestCommandRunnerEmptyCommand(t *testing.T) {
	runner := &CommandRunner{}

	_, err := runner.Run([]string{}, nil)

	require.Error(t, err)
	var taskErr *TaskError
	require.ErrorAs(t, err, &taskErr)
	require.Contains(t, taskErr.Message, "empty command")
}

func TestCommandRunnerWorkDir(t *testing.T) {
	// Create a temp directory
	tmpDir := t.TempDir()

	runner := &CommandRunner{
		WorkDir: tmpDir,
	}

	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "cd"}
	} else {
		cmd = []string{"pwd"}
	}

	output, err := runner.Run(cmd, nil)

	require.NoError(t, err)
	require.Equal(t, 0, output.ExitCode)
	require.Contains(t, output.Stdout, filepath.Base(tmpDir))
}

func TestCommandRunnerStderr(t *testing.T) {
	runner := &CommandRunner{}

	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "echo error 1>&2"}
	} else {
		cmd = []string{"sh", "-c", "echo error >&2"}
	}

	output, err := runner.Run(cmd, nil)

	require.NoError(t, err)
	require.Equal(t, 0, output.ExitCode)
	require.Contains(t, output.Stderr, "error")
}

func TestBuildEnv(t *testing.T) {
	env := map[string]string{
		"NEW_VAR":  "new_value",
		"PATH":     "/custom/path", // Override existing
		"TEST_VAR": "test",
	}

	result := buildEnv(env)

	// Check that new variables are present
	found := make(map[string]bool)
	for _, e := range result {
		if e == "NEW_VAR=new_value" {
			found["NEW_VAR"] = true
		}
		if e == "TEST_VAR=test" {
			found["TEST_VAR"] = true
		}
		if e == "PATH=/custom/path" {
			found["PATH"] = true
		}
	}

	require.True(t, found["NEW_VAR"])
	require.True(t, found["TEST_VAR"])
	require.True(t, found["PATH"])
}

func TestValidateMounts(t *testing.T) {
	t.Run("valid mounts", func(t *testing.T) {
		mounts := map[string]string{
			"workspace": "rw",
			"config":    "ro",
		}

		err := ValidateMounts(mounts, []string{"workspace"})
		require.NoError(t, err)
	})

	t.Run("missing mount", func(t *testing.T) {
		mounts := map[string]string{
			"config": "ro",
		}

		err := ValidateMounts(mounts, []string{"workspace"})
		require.Error(t, err)
		require.Contains(t, err.Error(), "not specified")
	})

	t.Run("wrong permission", func(t *testing.T) {
		mounts := map[string]string{
			"workspace": "ro",
		}

		err := ValidateMounts(mounts, []string{"workspace"})
		require.Error(t, err)
		require.Contains(t, err.Error(), "requires rw permission")
	})
}

func TestResolveCommand(t *testing.T) {
	t.Run("absolute path unchanged", func(t *testing.T) {
		cmd := []string{"/usr/bin/echo", "hello"}
		resolved, err := ResolveCommand(cmd, "/workspace")

		require.NoError(t, err)
		require.Equal(t, "/usr/bin/echo", resolved[0])
	})

	t.Run("relative path resolved", func(t *testing.T) {
		cmd := []string{"./scripts/build.sh"}
		resolved, err := ResolveCommand(cmd, "/workspace")

		require.NoError(t, err)
		require.Equal(t, "/workspace/scripts/build.sh", resolved[0])
	})

	t.Run("empty command error", func(t *testing.T) {
		_, err := ResolveCommand([]string{}, "/workspace")
		require.Error(t, err)
	})
}

func TestExecuteCommandTask(t *testing.T) {
	tmpDir := t.TempDir()
	ctx := newTestContextWithWorkspace(tmpDir)
	registry := NewTaskRegistry()

	// Use a simple echo command
	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "echo", "task output"}
	} else {
		cmd = []string{"echo", "task output"}
	}

	tasks := map[string]Task{
		"test-cmd": {
			Name: "test-cmd",
			Config: TaskConfig{
				Kind: TaskKindCommand,
				Cmd:  cmd,
			},
		},
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "test-cmd")

	require.NoError(t, err)
	require.Equal(t, "test-cmd", result.Name)
	require.NotNil(t, result.Output)
}

func TestExecuteCommandTaskWithEnv(t *testing.T) {
	tmpDir := t.TempDir()
	ctx := newTestContextWithWorkspace(tmpDir)
	registry := NewTaskRegistry()

	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "echo", "%CUSTOM_VAR%"}
	} else {
		cmd = []string{"sh", "-c", "echo $CUSTOM_VAR"}
	}

	tasks := map[string]Task{
		"test-env": {
			Name: "test-env",
			Config: TaskConfig{
				Kind: TaskKindCommand,
				Cmd:  cmd,
				Env: map[string]string{
					"CUSTOM_VAR": "custom_value",
				},
			},
		},
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "test-env")

	require.NoError(t, err)
	require.Contains(t, result.Output, "custom_value")
}

func TestExecuteCommandTaskFailure(t *testing.T) {
	tmpDir := t.TempDir()
	ctx := newTestContextWithWorkspace(tmpDir)
	registry := NewTaskRegistry()

	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "exit", "42"}
	} else {
		cmd = []string{"sh", "-c", "exit 42"}
	}

	tasks := map[string]Task{
		"test-fail": {
			Name: "test-fail",
			Config: TaskConfig{
				Kind: TaskKindCommand,
				Cmd:  cmd,
			},
		},
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "test-fail")

	require.Error(t, err)
	require.Equal(t, "test-fail", result.Name)
	require.NotEmpty(t, result.Diagnostics)
	require.Equal(t, "CMD_42", result.Diagnostics[0].Code)
}

func TestExecuteCommandTaskNoCmd(t *testing.T) {
	tmpDir := t.TempDir()
	ctx := newTestContextWithWorkspace(tmpDir)
	registry := NewTaskRegistry()

	tasks := map[string]Task{
		"no-cmd": {
			Name: "no-cmd",
			Config: TaskConfig{
				Kind: TaskKindCommand,
				Cmd:  []string{}, // Empty command
			},
		},
	}

	executor := NewExecutor(registry, tasks)
	_, err := executor.Execute(ctx, "no-cmd")

	require.Error(t, err)
	var taskErr *TaskError
	require.ErrorAs(t, err, &taskErr)
	require.Contains(t, taskErr.Message, "no command specified")
}

func TestExecuteCommandWithWorkDir(t *testing.T) {
	tmpDir := t.TempDir()

	// Create a test file in the temp dir
	testFile := filepath.Join(tmpDir, "test.txt")
	err := os.WriteFile(testFile, []byte("hello"), 0644)
	require.NoError(t, err)

	// Create context with tmpDir as workspace
	ctx := newTestContextWithWorkspace(tmpDir)
	registry := NewTaskRegistry()

	var cmd []string
	if runtime.GOOS == "windows" {
		cmd = []string{"cmd", "/c", "dir", "test.txt"}
	} else {
		cmd = []string{"ls", "test.txt"}
	}

	tasks := map[string]Task{
		"list-file": {
			Name: "list-file",
			Config: TaskConfig{
				Kind: TaskKindCommand,
				Cmd:  cmd,
			},
		},
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "list-file")

	require.NoError(t, err)
	require.Contains(t, result.Output, "test.txt")
}

func newTestContextWithWorkspace(workDir string) pipeline.Context {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	return pipeline.NewContext(workDir, 3, pipeline.ModeDefault, vfsInstance)
}
