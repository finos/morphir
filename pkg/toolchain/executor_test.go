package toolchain

import (
	"os"
	"testing"
	"time"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

func TestExecutor_ExecuteExternalTask(t *testing.T) {
	// Skip if echo command is not available
	if _, err := os.Stat("/bin/echo"); os.IsNotExist(err) {
		if _, err := os.Stat("/usr/bin/echo"); os.IsNotExist(err) {
			t.Skip("echo command not found")
		}
	}

	// Create test VFS
	vfsInstance := createTestVFS()

	// Create pipeline context
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)

	// Create output directory structure
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)

	// Create registry
	registry := NewRegistry()

	// Define a simple toolchain with echo task
	tc := Toolchain{
		Name:    "test-toolchain",
		Version: "1.0.0",
		Type:    ToolchainTypeExternal,
		Acquire: AcquireConfig{
			Backend:    "path",
			Executable: "echo",
		},
		Tasks: []TaskDef{
			{
				Name:        "echo-task",
				Description: "Simple echo task",
				Exec:        "echo",
				Args:        []string{"Hello", "World"},
				Outputs: map[string]OutputSpec{
					"stdout": {Path: "output.txt", Type: "text"},
				},
			},
		},
	}

	registry.Register(tc)

	// Create executor
	executor := NewExecutor(registry, outputDir, ctx)

	// Execute task
	result, err := executor.ExecuteTask("test-toolchain", "echo-task", "")
	if err != nil {
		t.Fatalf("unexpected error executing task: %v", err)
	}

	// Verify result
	if !result.Metadata.Success {
		t.Errorf("expected task to succeed, got failure")
	}

	if result.Metadata.ExitCode != 0 {
		t.Errorf("expected exit code 0, got %d", result.Metadata.ExitCode)
	}

	if result.Metadata.ToolchainName != "test-toolchain" {
		t.Errorf("expected toolchain name 'test-toolchain', got '%s'", result.Metadata.ToolchainName)
	}

	if result.Metadata.TaskName != "echo-task" {
		t.Errorf("expected task name 'echo-task', got '%s'", result.Metadata.TaskName)
	}

	if result.Metadata.Duration <= 0 {
		t.Error("expected duration to be positive")
	}

	// Verify metadata was written
	metaPath, err := outputDir.MetaPath("test-toolchain", "echo-task")
	if err != nil {
		t.Fatalf("unexpected error creating meta path: %v", err)
	}

	entry, _, err := vfsInstance.Resolve(metaPath)
	if err != nil {
		t.Errorf("metadata file not written: %v", err)
	} else {
		if entry.Kind() != vfs.KindFile {
			t.Errorf("expected metadata to be a file, got %s", entry.Kind())
		}
	}
}

func TestExecutor_ExecuteTask_ToolchainNotFound(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)

	_, err := executor.ExecuteTask("nonexistent", "task", "")
	if err == nil {
		t.Fatal("expected error for nonexistent toolchain")
	}

	expectedMsg := "toolchain not found"
	if err.Error()[:len(expectedMsg)] != expectedMsg {
		t.Errorf("expected error message to start with '%s', got '%s'", expectedMsg, err.Error())
	}
}

func TestExecutor_ExecuteTask_TaskNotFound(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()

	tc := Toolchain{
		Name: "test-toolchain",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{Name: "task-a"},
		},
	}
	registry.Register(tc)

	executor := NewExecutor(registry, outputDir, ctx)

	_, err := executor.ExecuteTask("test-toolchain", "nonexistent-task", "")
	if err == nil {
		t.Fatal("expected error for nonexistent task")
	}

	expectedMsg := "task not found"
	if err.Error()[:len(expectedMsg)] != expectedMsg {
		t.Errorf("expected error message to start with '%s', got '%s'", expectedMsg, err.Error())
	}
}

func TestExecutor_ExecuteTask_UnsupportedVariant(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()

	tc := Toolchain{
		Name: "test-toolchain",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "gen",
				Variants: []string{"scala", "typescript"},
			},
		},
	}
	registry.Register(tc)

	executor := NewExecutor(registry, outputDir, ctx)

	_, err := executor.ExecuteTask("test-toolchain", "gen", "python")
	if err == nil {
		t.Fatal("expected error for unsupported variant")
	}

	expectedMsg := "variant python not supported"
	if err.Error()[:len(expectedMsg)] != expectedMsg {
		t.Errorf("expected error message to start with '%s', got '%s'", expectedMsg, err.Error())
	}
}

func TestExecutor_SubstituteArgs(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)

	tc := Toolchain{
		Name: "test-toolchain",
		Type: ToolchainTypeExternal,
	}

	task := TaskDef{
		Name: "gen",
		Args: []string{"gen", "-t", "{variant}", "-o", "{outputs.code}"},
		Outputs: map[string]OutputSpec{
			"code": {Path: "generated.scala", Type: "code"},
		},
	}

	args, err := executor.substituteArgs(tc, task, "scala")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(args) != 5 {
		t.Fatalf("expected 5 args, got %d: %v", len(args), args)
	}

	if args[0] != "gen" {
		t.Errorf("expected args[0] = 'gen', got '%s'", args[0])
	}

	t.Logf("args after substitution: %v", args)

	if args[2] != "scala" {
		t.Errorf("expected args[2] = 'scala', got '%s'", args[2])
	}

	// args[4] should be the output path
	if args[4] == "{outputs.code}" {
		t.Error("output substitution did not occur")
	}
}

func TestExecutor_PrepareEnv(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)

	tc := Toolchain{
		Name: "test-toolchain",
		Type: ToolchainTypeExternal,
		Env: map[string]string{
			"TOOLCHAIN_VAR": "toolchain-value",
			"COMMON_VAR":    "toolchain-common",
		},
	}

	task := TaskDef{
		Name: "task",
		Env: map[string]string{
			"TASK_VAR":   "task-value",
			"COMMON_VAR": "task-override",
		},
	}

	env := executor.prepareEnv(tc, task)

	// Check that env contains our custom vars
	foundToolchainVar := false
	foundTaskVar := false
	foundCommonVar := false
	var commonVarValue string

	for _, e := range env {
		if e == "TOOLCHAIN_VAR=toolchain-value" {
			foundToolchainVar = true
		}
		if e == "TASK_VAR=task-value" {
			foundTaskVar = true
		}
		if len(e) > 11 && e[:11] == "COMMON_VAR=" {
			foundCommonVar = true
			commonVarValue = e[11:]
		}
	}

	if !foundToolchainVar {
		t.Error("expected TOOLCHAIN_VAR in environment")
	}

	if !foundTaskVar {
		t.Error("expected TASK_VAR in environment")
	}

	if !foundCommonVar {
		t.Error("expected COMMON_VAR in environment")
	}

	// Task env should override toolchain env
	if commonVarValue != "task-override" {
		t.Errorf("expected COMMON_VAR='task-override', got '%s'", commonVarValue)
	}
}

func TestExecutor_GetTimeout(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)

	// Test default timeout
	tc1 := Toolchain{Name: "tc1", Type: ToolchainTypeExternal}
	task1 := TaskDef{Name: "task1"}
	timeout1 := executor.getTimeout(tc1, task1)
	if timeout1 != 5*time.Minute {
		t.Errorf("expected default timeout of 5m, got %v", timeout1)
	}

	// Test toolchain timeout
	tc2 := Toolchain{Name: "tc2", Type: ToolchainTypeExternal, Timeout: 10 * time.Minute}
	task2 := TaskDef{Name: "task2"}
	timeout2 := executor.getTimeout(tc2, task2)
	if timeout2 != 10*time.Minute {
		t.Errorf("expected toolchain timeout of 10m, got %v", timeout2)
	}

	// Test task timeout overrides toolchain
	tc3 := Toolchain{Name: "tc3", Type: ToolchainTypeExternal, Timeout: 10 * time.Minute}
	task3 := TaskDef{Name: "task3", Timeout: 2 * time.Minute}
	timeout3 := executor.getTimeout(tc3, task3)
	if timeout3 != 2*time.Minute {
		t.Errorf("expected task timeout of 2m, got %v", timeout3)
	}
}
