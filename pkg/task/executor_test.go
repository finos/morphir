package task

import (
	"errors"
	"testing"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/require"
)

func newTestContext() pipeline.Context {
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{})
	return pipeline.NewContext("/workspace", 3, pipeline.ModeDefault, vfsInstance)
}

func TestTaskRegistryRegisterAndGet(t *testing.T) {
	registry := NewTaskRegistry()

	action := func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
		return "result", pipeline.StepResult{}
	}

	registry.Register("test.action", action)

	retrieved, ok := registry.Get("test.action")
	require.True(t, ok)
	require.NotNil(t, retrieved)
}

func TestTaskRegistryGetNonExistent(t *testing.T) {
	registry := NewTaskRegistry()

	_, ok := registry.Get("non.existent")
	require.False(t, ok)
}

func TestExecuteSimpleIntrinsicTask(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()

	// Register a simple intrinsic action
	registry.Register("test.echo", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
		return params["message"], pipeline.StepResult{}
	})

	tasks := map[string]Task{
		"echo": NewIntrinsicTask("echo", "test.echo",
			WithParams(map[string]any{"message": "hello world"})),
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "echo")

	require.NoError(t, err)
	require.Equal(t, "echo", result.Name)
	require.Equal(t, "hello world", result.Output)
	require.Empty(t, result.Diagnostics)
	require.Empty(t, result.Artifacts)
}

func TestExecuteIntrinsicTaskWithDiagnostics(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()

	registry.Register("test.validate", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
		diag := pipeline.Diagnostic{
			Severity: pipeline.SeverityWarn,
			Code:     "W001",
			Message:  "Test warning",
			StepName: "validate",
		}
		return "validated", pipeline.StepResult{
			Diagnostics: []pipeline.Diagnostic{diag},
		}
	})

	tasks := map[string]Task{
		"validate": NewIntrinsicTask("validate", "test.validate"),
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "validate")

	require.NoError(t, err)
	require.Equal(t, "validate", result.Name)
	require.Len(t, result.Diagnostics, 1)
	require.Equal(t, "W001", result.Diagnostics[0].Code)
}

func TestExecuteIntrinsicTaskWithError(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()

	expectedErr := errors.New("action failed")
	registry.Register("test.fail", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
		return nil, pipeline.StepResult{Err: expectedErr}
	})

	tasks := map[string]Task{
		"fail": NewIntrinsicTask("fail", "test.fail"),
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "fail")

	require.Error(t, err)
	require.ErrorIs(t, err, expectedErr)
	require.Equal(t, "fail", result.Name)
}

func TestExecuteTaskNotFound(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()
	executor := NewExecutor(registry, map[string]Task{})

	result, err := executor.Execute(ctx, "non-existent")

	require.Error(t, err)
	require.True(t, IsTaskNotFound(err))
	require.Equal(t, "", result.Name)
}

func TestExecuteTaskWithDependencies(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()

	executionOrder := []string{}

	registry.Register("test.step", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
		name := params["name"].(string)
		executionOrder = append(executionOrder, name)
		return name, pipeline.StepResult{}
	})

	tasks := map[string]Task{
		"a": NewIntrinsicTask("a", "test.step",
			WithParams(map[string]any{"name": "a"})),
		"b": NewIntrinsicTask("b", "test.step",
			WithDependsOn([]string{"a"}),
			WithParams(map[string]any{"name": "b"})),
		"c": NewIntrinsicTask("c", "test.step",
			WithDependsOn([]string{"a", "b"}),
			WithParams(map[string]any{"name": "c"})),
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "c")

	require.NoError(t, err)
	require.Equal(t, "c", result.Name)
	require.Equal(t, "c", result.Output)

	// Check execution order: a, b, c
	require.Equal(t, []string{"a", "b", "c"}, executionOrder)
	require.Contains(t, result.Dependencies, "a")
	require.Contains(t, result.Dependencies, "b")
}

func TestExecuteTaskWithPreHook(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()

	executionOrder := []string{}

	registry.Register("test.step", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
		name := params["name"].(string)
		executionOrder = append(executionOrder, name)
		return name, pipeline.StepResult{}
	})

	tasks := map[string]Task{
		"setup": NewIntrinsicTask("setup", "test.step",
			WithParams(map[string]any{"name": "setup"})),
		"main": NewIntrinsicTask("main", "test.step",
			WithPre([]string{"setup"}),
			WithParams(map[string]any{"name": "main"})),
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "main")

	require.NoError(t, err)
	require.Equal(t, "main", result.Name)
	require.Equal(t, []string{"setup", "main"}, executionOrder)
	require.Contains(t, result.Dependencies, "setup")
}

func TestExecuteTaskWithPostHook(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()

	executionOrder := []string{}

	registry.Register("test.step", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
		name := params["name"].(string)
		executionOrder = append(executionOrder, name)
		return name, pipeline.StepResult{}
	})

	tasks := map[string]Task{
		"cleanup": NewIntrinsicTask("cleanup", "test.step",
			WithParams(map[string]any{"name": "cleanup"})),
		"main": NewIntrinsicTask("main", "test.step",
			WithPost([]string{"cleanup"}),
			WithParams(map[string]any{"name": "main"})),
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "main")

	require.NoError(t, err)
	require.Equal(t, "main", result.Name)
	require.Equal(t, []string{"main", "cleanup"}, executionOrder)
	require.Contains(t, result.Dependencies, "cleanup")
}

func TestExecuteTaskWithPreAndPostHooks(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()

	executionOrder := []string{}

	registry.Register("test.step", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
		name := params["name"].(string)
		executionOrder = append(executionOrder, name)
		return name, pipeline.StepResult{}
	})

	tasks := map[string]Task{
		"setup": NewIntrinsicTask("setup", "test.step",
			WithParams(map[string]any{"name": "setup"})),
		"cleanup": NewIntrinsicTask("cleanup", "test.step",
			WithParams(map[string]any{"name": "cleanup"})),
		"main": NewIntrinsicTask("main", "test.step",
			WithPre([]string{"setup"}),
			WithPost([]string{"cleanup"}),
			WithParams(map[string]any{"name": "main"})),
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "main")

	require.NoError(t, err)
	require.Equal(t, "main", result.Name)
	require.Equal(t, []string{"setup", "main", "cleanup"}, executionOrder)
	require.Contains(t, result.Dependencies, "setup")
	require.Contains(t, result.Dependencies, "cleanup")
}

func TestExecuteIntrinsicActionNotFound(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()

	tasks := map[string]Task{
		"test": NewIntrinsicTask("test", "non.existent"),
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "test")

	require.Error(t, err)
	require.Equal(t, "test", result.Name)

	var taskErr *TaskError
	require.ErrorAs(t, err, &taskErr)
	require.Contains(t, taskErr.Message, "intrinsic action not found")
}

// Note: TestExecuteUnknownTaskKind is no longer needed with typestate pattern
// since the type system now prevents unknown task kinds at compile time

func TestDuplicateDependencies(t *testing.T) {
	ctx := newTestContext()
	registry := NewTaskRegistry()

	executionOrder := []string{}

	registry.Register("test.step", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
		name := params["name"].(string)
		executionOrder = append(executionOrder, name)
		return name, pipeline.StepResult{}
	})

	// Diamond dependency: d depends on b and c, both depend on a
	// a should only be executed once
	tasks := map[string]Task{
		"a": NewIntrinsicTask("a", "test.step",
			WithParams(map[string]any{"name": "a"})),
		"b": NewIntrinsicTask("b", "test.step",
			WithDependsOn([]string{"a"}),
			WithParams(map[string]any{"name": "b"})),
		"c": NewIntrinsicTask("c", "test.step",
			WithDependsOn([]string{"a"}),
			WithParams(map[string]any{"name": "c"})),
		"d": NewIntrinsicTask("d", "test.step",
			WithDependsOn([]string{"b", "c"}),
			WithParams(map[string]any{"name": "d"})),
	}

	executor := NewExecutor(registry, tasks)
	result, err := executor.Execute(ctx, "d")

	require.NoError(t, err)
	require.Equal(t, "d", result.Name)

	// a should only be executed once, even though both b and c depend on it
	aCount := 0
	for _, name := range executionOrder {
		if name == "a" {
			aCount++
		}
	}
	require.Equal(t, 1, aCount, "Task 'a' should only be executed once")
}
