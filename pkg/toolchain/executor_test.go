package toolchain

import (
	"fmt"
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

func TestExecutor_ExecuteNativeTask(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()

	// Create a native handler that returns success
	successHandler := func(ctx pipeline.Context, input TaskInput) TaskResult {
		return TaskResult{
			Outputs: map[string]any{
				"result": "success",
			},
			Diagnostics: []pipeline.Diagnostic{
				{
					Severity: pipeline.SeverityInfo,
					Message:  "Task completed successfully",
				},
			},
		}
	}

	tc := Toolchain{
		Name: "native-toolchain",
		Type: ToolchainTypeNative,
		Tasks: []TaskDef{
			{
				Name:        "native-task",
				Description: "A native task",
				Handler:     successHandler,
				Fulfills:    []string{"make"},
			},
		},
	}
	registry.Register(tc)

	executor := NewExecutor(registry, outputDir, ctx)

	result, err := executor.ExecuteTask("native-toolchain", "native-task", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !result.Metadata.Success {
		t.Error("expected task to succeed")
	}

	if result.Metadata.ToolchainName != "native-toolchain" {
		t.Errorf("expected toolchain name 'native-toolchain', got '%s'", result.Metadata.ToolchainName)
	}

	if result.Metadata.TaskName != "native-task" {
		t.Errorf("expected task name 'native-task', got '%s'", result.Metadata.TaskName)
	}

	if result.Outputs["result"] != "success" {
		t.Errorf("expected output 'result'='success', got %v", result.Outputs["result"])
	}

	if len(result.Diagnostics) != 1 {
		t.Errorf("expected 1 diagnostic, got %d", len(result.Diagnostics))
	}
}

func TestExecutor_ExecuteNativeTask_WithError(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()

	// Create a native handler that returns an error
	errorHandler := func(ctx pipeline.Context, input TaskInput) TaskResult {
		return TaskResult{
			Error: fmt.Errorf("something went wrong"),
			Diagnostics: []pipeline.Diagnostic{
				{
					Severity: pipeline.SeverityError,
					Code:     "NATIVE_ERR",
					Message:  "something went wrong",
				},
			},
		}
	}

	tc := Toolchain{
		Name: "native-toolchain",
		Type: ToolchainTypeNative,
		Tasks: []TaskDef{
			{
				Name:    "failing-task",
				Handler: errorHandler,
			},
		},
	}
	registry.Register(tc)

	executor := NewExecutor(registry, outputDir, ctx)

	result, err := executor.ExecuteTask("native-toolchain", "failing-task", "")
	if err != nil {
		t.Fatalf("unexpected error from executor: %v", err)
	}

	if result.Metadata.Success {
		t.Error("expected task to fail")
	}

	if result.Error == nil {
		t.Error("expected error in result")
	}
}

func TestExecutor_ExecuteNativeTask_MissingHandler(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()

	tc := Toolchain{
		Name: "native-toolchain",
		Type: ToolchainTypeNative,
		Tasks: []TaskDef{
			{
				Name:    "no-handler-task",
				Handler: nil, // Missing handler
			},
		},
	}
	registry.Register(tc)

	executor := NewExecutor(registry, outputDir, ctx)

	_, err := executor.ExecuteTask("native-toolchain", "no-handler-task", "")
	if err == nil {
		t.Fatal("expected error for missing handler")
	}

	expectedMsg := "native task no-handler-task has no handler"
	if err.Error() != expectedMsg {
		t.Errorf("expected error message '%s', got '%s'", expectedMsg, err.Error())
	}
}

func TestExecutor_ExecuteNativeTask_WithVariant(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()

	// Create a native handler that uses the variant
	variantHandler := func(ctx pipeline.Context, input TaskInput) TaskResult {
		return TaskResult{
			Outputs: map[string]any{
				"variant": input.Variant,
			},
		}
	}

	tc := Toolchain{
		Name: "native-toolchain",
		Type: ToolchainTypeNative,
		Tasks: []TaskDef{
			{
				Name:     "gen",
				Handler:  variantHandler,
				Variants: []string{"scala", "typescript"},
			},
		},
	}
	registry.Register(tc)

	executor := NewExecutor(registry, outputDir, ctx)

	result, err := executor.ExecuteTask("native-toolchain", "gen", "scala")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Outputs["variant"] != "scala" {
		t.Errorf("expected variant 'scala', got '%v'", result.Outputs["variant"])
	}
}

func TestExecutor_ResolveNpxExecutable(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)

	t.Run("npx backend requires package", func(t *testing.T) {
		tc := Toolchain{
			Name: "test-toolchain",
			Type: ToolchainTypeExternal,
			Acquire: AcquireConfig{
				Backend: "npx",
				Package: "", // Missing package
			},
		}
		task := TaskDef{Name: "task"}

		_, err := executor.resolveExecutable(tc, task)
		if err == nil {
			t.Fatal("expected error for missing package")
		}

		if err.Error() != "package must be specified for npx backend" {
			t.Errorf("unexpected error message: %s", err.Error())
		}
	})

	t.Run("npx backend with valid package", func(t *testing.T) {
		// Skip if PATH is not set (shouldn't normally happen)
		if _, ok := os.LookupEnv("PATH"); !ok {
			t.Skip("PATH not set")
		}

		tc := Toolchain{
			Name: "test-toolchain",
			Type: ToolchainTypeExternal,
			Acquire: AcquireConfig{
				Backend: "npx",
				Package: "morphir-elm",
				Version: "2.90.0",
			},
		}
		task := TaskDef{Name: "task"}

		executable, err := executor.resolveExecutable(tc, task)
		if err != nil {
			// If npx is not installed, skip
			if err.Error()[:14] == "npx not found" {
				t.Skip("npx not installed")
			}
			t.Fatalf("unexpected error: %v", err)
		}

		// Should resolve to npx path
		if executable == "" {
			t.Error("expected executable path, got empty string")
		}
	})
}

func TestExecutor_BuildNpxArgs(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)

	t.Run("builds args with package and version", func(t *testing.T) {
		tc := Toolchain{
			Name: "morphir-elm",
			Acquire: AcquireConfig{
				Backend: "npx",
				Package: "morphir-elm",
				Version: "2.90.0",
			},
		}
		task := TaskDef{Name: "make"}
		taskArgs := []string{"make", "-o", "morphir-ir.json"}

		npxArgs := executor.buildNpxArgs(tc, task, taskArgs)

		// Expected: ["-y", "morphir-elm@2.90.0", "make", "-o", "morphir-ir.json"]
		if len(npxArgs) != 5 {
			t.Fatalf("expected 5 args, got %d: %v", len(npxArgs), npxArgs)
		}

		if npxArgs[0] != "-y" {
			t.Errorf("expected npxArgs[0] = '-y', got '%s'", npxArgs[0])
		}

		if npxArgs[1] != "morphir-elm@2.90.0" {
			t.Errorf("expected npxArgs[1] = 'morphir-elm@2.90.0', got '%s'", npxArgs[1])
		}

		if npxArgs[2] != "make" {
			t.Errorf("expected npxArgs[2] = 'make', got '%s'", npxArgs[2])
		}
	})

	t.Run("builds args without version", func(t *testing.T) {
		tc := Toolchain{
			Name: "morphir-elm",
			Acquire: AcquireConfig{
				Backend: "npx",
				Package: "morphir-elm",
				// No version
			},
		}
		task := TaskDef{Name: "make"}
		taskArgs := []string{"make"}

		npxArgs := executor.buildNpxArgs(tc, task, taskArgs)

		// Expected: ["-y", "morphir-elm", "make"]
		if len(npxArgs) != 3 {
			t.Fatalf("expected 3 args, got %d: %v", len(npxArgs), npxArgs)
		}

		if npxArgs[1] != "morphir-elm" {
			t.Errorf("expected npxArgs[1] = 'morphir-elm', got '%s'", npxArgs[1])
		}
	})
}

func TestExecutor_ResolveBunxExecutable(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)

	t.Run("bunx backend requires package", func(t *testing.T) {
		tc := Toolchain{
			Name: "test-toolchain",
			Type: ToolchainTypeExternal,
			Acquire: AcquireConfig{
				Backend: "bunx",
				Package: "", // Missing package
			},
		}
		task := TaskDef{Name: "task"}

		_, err := executor.resolveExecutable(tc, task)
		if err == nil {
			t.Fatal("expected error for missing package")
		}

		if err.Error() != "package must be specified for bunx backend" {
			t.Errorf("unexpected error message: %s", err.Error())
		}
	})

	t.Run("bunx backend with valid package", func(t *testing.T) {
		// Skip if PATH is not set (shouldn't normally happen)
		if _, ok := os.LookupEnv("PATH"); !ok {
			t.Skip("PATH not set")
		}

		tc := Toolchain{
			Name: "test-toolchain",
			Type: ToolchainTypeExternal,
			Acquire: AcquireConfig{
				Backend: "bunx",
				Package: "morphir-elm",
				Version: "2.90.0",
			},
		}
		task := TaskDef{Name: "task"}

		executable, err := executor.resolveExecutable(tc, task)
		if err != nil {
			// If bunx is not installed, skip
			if len(err.Error()) >= 14 && err.Error()[:14] == "bunx not found" {
				t.Skip("bunx not installed")
			}
			t.Fatalf("unexpected error: %v", err)
		}

		// Should resolve to bunx path
		if executable == "" {
			t.Error("expected executable path, got empty string")
		}
	})
}

func TestExecutor_BuildBunxArgs(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)

	t.Run("builds args with package and version", func(t *testing.T) {
		tc := Toolchain{
			Name: "morphir-elm",
			Acquire: AcquireConfig{
				Backend: "bunx",
				Package: "morphir-elm",
				Version: "2.90.0",
			},
		}
		task := TaskDef{Name: "make"}
		taskArgs := []string{"make", "-o", "morphir-ir.json"}

		bunxArgs := executor.buildBunxArgs(tc, task, taskArgs)

		// Expected: ["morphir-elm@2.90.0", "make", "-o", "morphir-ir.json"]
		// Note: bunx doesn't need -y flag like npx
		if len(bunxArgs) != 4 {
			t.Fatalf("expected 4 args, got %d: %v", len(bunxArgs), bunxArgs)
		}

		if bunxArgs[0] != "morphir-elm@2.90.0" {
			t.Errorf("expected bunxArgs[0] = 'morphir-elm@2.90.0', got '%s'", bunxArgs[0])
		}

		if bunxArgs[1] != "make" {
			t.Errorf("expected bunxArgs[1] = 'make', got '%s'", bunxArgs[1])
		}
	})

	t.Run("builds args without version", func(t *testing.T) {
		tc := Toolchain{
			Name: "morphir-elm",
			Acquire: AcquireConfig{
				Backend: "bunx",
				Package: "morphir-elm",
				// No version
			},
		}
		task := TaskDef{Name: "make"}
		taskArgs := []string{"make"}

		bunxArgs := executor.buildBunxArgs(tc, task, taskArgs)

		// Expected: ["morphir-elm", "make"]
		if len(bunxArgs) != 2 {
			t.Fatalf("expected 2 args, got %d: %v", len(bunxArgs), bunxArgs)
		}

		if bunxArgs[0] != "morphir-elm" {
			t.Errorf("expected bunxArgs[0] = 'morphir-elm', got '%s'", bunxArgs[0])
		}
	})
}

func TestExecutor_ResolveExecutable_Backends(t *testing.T) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)

	t.Run("unsupported backend returns error", func(t *testing.T) {
		tc := Toolchain{
			Name: "test-toolchain",
			Type: ToolchainTypeExternal,
			Acquire: AcquireConfig{
				Backend: "docker", // Not implemented
			},
		}
		task := TaskDef{Name: "task"}

		_, err := executor.resolveExecutable(tc, task)
		if err == nil {
			t.Fatal("expected error for unsupported backend")
		}

		expectedMsg := "acquisition backend docker not yet implemented"
		if err.Error() != expectedMsg {
			t.Errorf("expected '%s', got '%s'", expectedMsg, err.Error())
		}
	})

	t.Run("empty backend defaults to path", func(t *testing.T) {
		tc := Toolchain{
			Name: "test-toolchain",
			Type: ToolchainTypeExternal,
			Acquire: AcquireConfig{
				Backend:    "", // Empty defaults to path
				Executable: "echo",
			},
		}
		task := TaskDef{Name: "task"}

		executable, err := executor.resolveExecutable(tc, task)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		// Should resolve to echo
		if executable == "" {
			t.Error("expected executable path")
		}
	})
}
