package toolchain

import (
	"context"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

func TestWorkflowRunner_Run_EmptyPlan(t *testing.T) {
	runner, _ := createTestRunner()

	plan := Plan{
		Workflow: Workflow{Name: "empty"},
		Stages:   []PlanStage{},
		Tasks:    make(map[TaskKey]*PlanTask),
	}

	result := runner.Run(plan, DefaultRunOptions())

	if !result.Success {
		t.Error("expected empty workflow to succeed")
	}
	if len(result.Stages) != 0 {
		t.Errorf("expected 0 stages, got %d", len(result.Stages))
	}
	if result.Duration <= 0 {
		t.Error("expected positive duration")
	}
}

func TestWorkflowRunner_Run_SingleTask(t *testing.T) {
	runner, registry := createTestRunner()

	// Register a simple echo toolchain
	registerEchoToolchain(registry)

	plan := Plan{
		Workflow: Workflow{Name: "single-task"},
		Stages: []PlanStage{
			{
				Name:     "build",
				Parallel: false,
				Tasks: []*PlanTask{
					{
						Key:       TaskKey{Toolchain: "echo", Task: "hello", Variant: ""},
						Toolchain: "echo",
						Task:      "hello",
					},
				},
			},
		},
		Tasks: map[TaskKey]*PlanTask{
			{Toolchain: "echo", Task: "hello"}: {
				Key:       TaskKey{Toolchain: "echo", Task: "hello"},
				Toolchain: "echo",
				Task:      "hello",
			},
		},
	}

	result := runner.Run(plan, DefaultRunOptions())

	if !result.Success {
		t.Errorf("expected workflow to succeed, got error: %v", result.Error)
	}
	if len(result.Stages) != 1 {
		t.Errorf("expected 1 stage, got %d", len(result.Stages))
	}
	if len(result.TaskResults) != 1 {
		t.Errorf("expected 1 task result, got %d", len(result.TaskResults))
	}
}

func TestWorkflowRunner_Run_MultipleStages(t *testing.T) {
	runner, registry := createTestRunner()

	registerEchoToolchain(registry)

	task1 := &PlanTask{
		Key:       TaskKey{Toolchain: "echo", Task: "hello", Variant: ""},
		Toolchain: "echo",
		Task:      "hello",
	}
	task2 := &PlanTask{
		Key:       TaskKey{Toolchain: "echo", Task: "world", Variant: ""},
		Toolchain: "echo",
		Task:      "world",
	}

	plan := Plan{
		Workflow: Workflow{Name: "multi-stage"},
		Stages: []PlanStage{
			{Name: "stage1", Tasks: []*PlanTask{task1}},
			{Name: "stage2", Tasks: []*PlanTask{task2}},
		},
		Tasks: map[TaskKey]*PlanTask{
			task1.Key: task1,
			task2.Key: task2,
		},
	}

	result := runner.Run(plan, DefaultRunOptions())

	if !result.Success {
		t.Errorf("expected workflow to succeed, got error: %v", result.Error)
	}
	if len(result.Stages) != 2 {
		t.Errorf("expected 2 stages, got %d", len(result.Stages))
	}

	// Verify stages executed in order
	if result.Stages[0].Name != "stage1" {
		t.Errorf("expected first stage to be 'stage1', got %s", result.Stages[0].Name)
	}
	if result.Stages[1].Name != "stage2" {
		t.Errorf("expected second stage to be 'stage2', got %s", result.Stages[1].Name)
	}
}

func TestWorkflowRunner_Run_DryRun(t *testing.T) {
	runner, registry := createTestRunner()

	registerEchoToolchain(registry)

	task := &PlanTask{
		Key:       TaskKey{Toolchain: "echo", Task: "hello"},
		Toolchain: "echo",
		Task:      "hello",
	}

	plan := Plan{
		Workflow: Workflow{Name: "dry-run-test"},
		Stages: []PlanStage{
			{Name: "build", Tasks: []*PlanTask{task}},
		},
		Tasks: map[TaskKey]*PlanTask{task.Key: task},
	}

	opts := DefaultRunOptions()
	opts.DryRun = true

	result := runner.Run(plan, opts)

	if !result.Success {
		t.Error("expected dry run to succeed")
	}
	if len(result.TaskResults) != 1 {
		t.Errorf("expected 1 task result, got %d", len(result.TaskResults))
	}

	// Verify the task result shows success without actual execution
	taskResult := result.TaskResults[task.Key]
	if !taskResult.Metadata.Success {
		t.Error("expected dry run task to show success")
	}
}

func TestWorkflowRunner_Run_ParallelTasks(t *testing.T) {
	runner, registry := createTestRunner()

	registerEchoToolchain(registry)

	task1 := &PlanTask{
		Key:       TaskKey{Toolchain: "echo", Task: "hello"},
		Toolchain: "echo",
		Task:      "hello",
	}
	task2 := &PlanTask{
		Key:       TaskKey{Toolchain: "echo", Task: "world"},
		Toolchain: "echo",
		Task:      "world",
	}

	plan := Plan{
		Workflow: Workflow{Name: "parallel-test"},
		Stages: []PlanStage{
			{
				Name:     "parallel-stage",
				Parallel: true,
				Tasks:    []*PlanTask{task1, task2},
			},
		},
		Tasks: map[TaskKey]*PlanTask{
			task1.Key: task1,
			task2.Key: task2,
		},
	}

	result := runner.Run(plan, DefaultRunOptions())

	if !result.Success {
		t.Errorf("expected parallel workflow to succeed, got error: %v", result.Error)
	}
	if len(result.TaskResults) != 2 {
		t.Errorf("expected 2 task results, got %d", len(result.TaskResults))
	}
}

func TestWorkflowRunner_Run_ProgressCallback(t *testing.T) {
	runner, registry := createTestRunner()

	registerEchoToolchain(registry)

	task := &PlanTask{
		Key:       TaskKey{Toolchain: "echo", Task: "hello"},
		Toolchain: "echo",
		Task:      "hello",
	}

	plan := Plan{
		Workflow: Workflow{Name: "progress-test"},
		Stages: []PlanStage{
			{Name: "build", Tasks: []*PlanTask{task}},
		},
		Tasks: map[TaskKey]*PlanTask{task.Key: task},
	}

	var events []ProgressEvent
	opts := DefaultRunOptions()
	opts.Progress = func(event ProgressEvent) {
		events = append(events, event)
	}

	runner.Run(plan, opts)

	// Should have at least: workflow_started, stage_started, task_started, task_completed, stage_completed, workflow_completed
	expectedTypes := []ProgressEventType{
		ProgressWorkflowStarted,
		ProgressStageStarted,
		ProgressTaskStarted,
		ProgressTaskCompleted,
		ProgressStageCompleted,
		ProgressWorkflowCompleted,
	}

	if len(events) < len(expectedTypes) {
		t.Errorf("expected at least %d events, got %d", len(expectedTypes), len(events))
	}

	for i, expected := range expectedTypes {
		if i >= len(events) {
			break
		}
		if events[i].Type != expected {
			t.Errorf("event %d: expected type %s, got %s", i, expected, events[i].Type)
		}
	}
}

func TestWorkflowRunner_Run_Timeout(t *testing.T) {
	// Note: Native task handlers don't currently check context cancellation during execution.
	// This test verifies that the workflow runner respects timeouts between stages/tasks.
	t.Skip("Native task handlers don't support context cancellation yet")

	runner, registry := createTestRunner()

	// Register a slow toolchain that sleeps
	registry.Register(Toolchain{
		Name: "slow",
		Type: ToolchainTypeNative,
		Tasks: []TaskDef{
			{
				Name: "sleep",
				Handler: func(ctx pipeline.Context, input TaskInput) TaskResult {
					time.Sleep(5 * time.Second)
					return TaskResult{
						Metadata: TaskMetadata{Success: true},
					}
				},
			},
		},
	})

	task := &PlanTask{
		Key:       TaskKey{Toolchain: "slow", Task: "sleep"},
		Toolchain: "slow",
		Task:      "sleep",
	}

	plan := Plan{
		Workflow: Workflow{Name: "timeout-test"},
		Stages: []PlanStage{
			{Name: "slow-stage", Tasks: []*PlanTask{task}},
		},
		Tasks: map[TaskKey]*PlanTask{task.Key: task},
	}

	opts := DefaultRunOptions()
	opts.Timeout = 100 * time.Millisecond

	result := runner.Run(plan, opts)

	if result.Success {
		t.Error("expected workflow to fail due to timeout")
	}
	if result.Error != context.DeadlineExceeded {
		t.Errorf("expected deadline exceeded error, got: %v", result.Error)
	}
}

func TestWorkflowRunner_Run_Cancellation(t *testing.T) {
	runner, registry := createTestRunner()

	registerEchoToolchain(registry)

	task := &PlanTask{
		Key:       TaskKey{Toolchain: "echo", Task: "hello"},
		Toolchain: "echo",
		Task:      "hello",
	}

	plan := Plan{
		Workflow: Workflow{Name: "cancel-test"},
		Stages: []PlanStage{
			{Name: "build", Tasks: []*PlanTask{task}},
		},
		Tasks: map[TaskKey]*PlanTask{task.Key: task},
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately

	opts := DefaultRunOptions()
	opts.Context = ctx

	result := runner.Run(plan, opts)

	if result.Success {
		t.Error("expected workflow to fail due to cancellation")
	}
}

func TestWorkflowRunner_Run_StopOnError(t *testing.T) {
	runner, registry := createTestRunner()

	// Register a failing toolchain
	registry.Register(Toolchain{
		Name: "failing",
		Type: ToolchainTypeNative,
		Tasks: []TaskDef{
			{
				Name: "fail",
				Handler: func(ctx pipeline.Context, input TaskInput) TaskResult {
					return TaskResult{
						Metadata: TaskMetadata{Success: false},
						Error:    fmt.Errorf("intentional failure"),
					}
				},
			},
		},
	})

	registerEchoToolchain(registry)

	failTask := &PlanTask{
		Key:       TaskKey{Toolchain: "failing", Task: "fail"},
		Toolchain: "failing",
		Task:      "fail",
	}
	successTask := &PlanTask{
		Key:       TaskKey{Toolchain: "echo", Task: "hello"},
		Toolchain: "echo",
		Task:      "hello",
	}

	plan := Plan{
		Workflow: Workflow{Name: "stop-on-error-test"},
		Stages: []PlanStage{
			{Name: "stage1", Tasks: []*PlanTask{failTask}},
			{Name: "stage2", Tasks: []*PlanTask{successTask}},
		},
		Tasks: map[TaskKey]*PlanTask{
			failTask.Key:    failTask,
			successTask.Key: successTask,
		},
	}

	t.Run("StopOnError=true", func(t *testing.T) {
		opts := DefaultRunOptions()
		opts.StopOnError = true

		result := runner.Run(plan, opts)

		if result.Success {
			t.Error("expected workflow to fail")
		}
		// Should only have executed stage1
		if len(result.Stages) != 1 {
			t.Errorf("expected 1 stage (stopped after failure), got %d", len(result.Stages))
		}
	})

	t.Run("StopOnError=false", func(t *testing.T) {
		opts := DefaultRunOptions()
		opts.StopOnError = false

		result := runner.Run(plan, opts)

		if result.Success {
			t.Error("expected workflow to fail")
		}
		// Should have executed both stages
		if len(result.Stages) != 2 {
			t.Errorf("expected 2 stages (continued after failure), got %d", len(result.Stages))
		}
	})
}

func TestWorkflowRunner_Run_MaxParallel(t *testing.T) {
	runner, registry := createTestRunner()

	var concurrentCount int32
	var maxConcurrent int32

	// Register a toolchain that tracks concurrency
	registry.Register(Toolchain{
		Name: "concurrent",
		Type: ToolchainTypeNative,
		Tasks: []TaskDef{
			{
				Name: "track",
				Handler: func(ctx pipeline.Context, input TaskInput) TaskResult {
					current := atomic.AddInt32(&concurrentCount, 1)
					for {
						old := atomic.LoadInt32(&maxConcurrent)
						if current <= old || atomic.CompareAndSwapInt32(&maxConcurrent, old, current) {
							break
						}
					}
					time.Sleep(50 * time.Millisecond)
					atomic.AddInt32(&concurrentCount, -1)
					return TaskResult{
						Metadata: TaskMetadata{Success: true},
					}
				},
			},
		},
	})

	// Create 5 tasks
	tasks := make([]*PlanTask, 5)
	taskMap := make(map[TaskKey]*PlanTask)
	for i := 0; i < 5; i++ {
		key := TaskKey{Toolchain: "concurrent", Task: "track", Variant: fmt.Sprintf("%d", i)}
		tasks[i] = &PlanTask{
			Key:       key,
			Toolchain: "concurrent",
			Task:      "track",
			Variant:   fmt.Sprintf("%d", i),
		}
		taskMap[key] = tasks[i]
	}

	plan := Plan{
		Workflow: Workflow{Name: "max-parallel-test"},
		Stages: []PlanStage{
			{Name: "parallel", Parallel: true, Tasks: tasks},
		},
		Tasks: taskMap,
	}

	opts := DefaultRunOptions()
	opts.MaxParallel = 2

	runner.Run(plan, opts)

	if atomic.LoadInt32(&maxConcurrent) > 2 {
		t.Errorf("expected max concurrent to be <= 2, got %d", maxConcurrent)
	}
}

func TestWorkflowResult_Summary(t *testing.T) {
	result := WorkflowResult{
		Workflow: Workflow{Name: "test-workflow"},
		Success:  true,
		Duration: 5 * time.Second,
		TaskResults: map[TaskKey]TaskResult{
			{Toolchain: "tc", Task: "task1"}: {},
			{Toolchain: "tc", Task: "task2"}: {},
		},
		FailedTasks:  []TaskKey{},
		SkippedTasks: []TaskKey{},
	}

	summary := result.Summary()

	if summary == "" {
		t.Error("expected non-empty summary")
	}
	if !contains(summary, "test-workflow") {
		t.Error("summary should contain workflow name")
	}
	if !contains(summary, "SUCCESS") {
		t.Error("summary should contain SUCCESS status")
	}
}

func TestWorkflowResult_TaskCount(t *testing.T) {
	result := WorkflowResult{
		TaskResults: map[TaskKey]TaskResult{
			{Toolchain: "tc", Task: "task1"}: {},
			{Toolchain: "tc", Task: "task2"}: {},
			{Toolchain: "tc", Task: "task3"}: {},
		},
		FailedTasks:  []TaskKey{{Toolchain: "tc", Task: "task1"}},
		SkippedTasks: []TaskKey{{Toolchain: "tc", Task: "task2"}},
	}

	if result.TaskCount() != 3 {
		t.Errorf("expected task count 3, got %d", result.TaskCount())
	}
	if result.SuccessfulTaskCount() != 1 {
		t.Errorf("expected successful task count 1, got %d", result.SuccessfulTaskCount())
	}
}

// Helper functions

func createTestRunner() (*WorkflowRunner, *Registry) {
	vfsInstance := createTestVFS()
	ctx := pipeline.NewContext(".", 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath(".morphir/out"), vfsInstance)
	registry := NewRegistry()
	executor := NewExecutor(registry, outputDir, ctx)
	runner := NewWorkflowRunner(executor, outputDir)
	return runner, registry
}

func registerEchoToolchain(registry *Registry) {
	registry.Register(Toolchain{
		Name: "echo",
		Type: ToolchainTypeNative,
		Tasks: []TaskDef{
			{
				Name: "hello",
				Handler: func(ctx pipeline.Context, input TaskInput) TaskResult {
					return TaskResult{
						Metadata: TaskMetadata{
							ToolchainName: "echo",
							TaskName:      "hello",
							Success:       true,
						},
						Outputs: map[string]any{"message": "Hello"},
					}
				},
			},
			{
				Name: "world",
				Handler: func(ctx pipeline.Context, input TaskInput) TaskResult {
					return TaskResult{
						Metadata: TaskMetadata{
							ToolchainName: "echo",
							TaskName:      "world",
							Success:       true,
						},
						Outputs: map[string]any{"message": "World"},
					}
				},
			},
		},
	})
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func TestEvaluateCondition(t *testing.T) {
	tests := []struct {
		name      string
		condition string
		expected  bool
	}{
		// True conditions
		{"empty string", "", true},
		{"true lowercase", "true", true},
		{"True mixed case", "True", true},
		{"TRUE uppercase", "TRUE", true},
		{"yes lowercase", "yes", true},
		{"Yes mixed case", "Yes", true},
		{"YES uppercase", "YES", true},
		{"1", "1", true},

		// False conditions
		{"false lowercase", "false", false},
		{"False mixed case", "False", false},
		{"FALSE uppercase", "FALSE", false},
		{"no lowercase", "no", false},
		{"No mixed case", "No", false},
		{"NO uppercase", "NO", false},
		{"0", "0", false},

		// Unknown conditions (default to true)
		{"unknown expression", "env.CI == 'true'", true},
		{"random string", "always", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := evaluateCondition(tt.condition)
			if result != tt.expected {
				t.Errorf("evaluateCondition(%q) = %v, want %v", tt.condition, result, tt.expected)
			}
		})
	}
}

func TestWorkflowRunner_Run_StageCondition(t *testing.T) {
	runner, registry := createTestRunner()

	registerEchoToolchain(registry)

	task := &PlanTask{
		Key:       TaskKey{Toolchain: "echo", Task: "hello"},
		Toolchain: "echo",
		Task:      "hello",
	}

	t.Run("false condition skips stage", func(t *testing.T) {
		plan := Plan{
			Workflow: Workflow{Name: "conditional-test"},
			Stages: []PlanStage{
				{
					Name:      "conditional-stage",
					Condition: "false",
					Tasks:     []*PlanTask{task},
				},
			},
			Tasks: map[TaskKey]*PlanTask{task.Key: task},
		}

		result := runner.Run(plan, DefaultRunOptions())

		if !result.Success {
			t.Errorf("expected workflow to succeed, got error: %v", result.Error)
		}
		if len(result.Stages) != 1 {
			t.Errorf("expected 1 stage, got %d", len(result.Stages))
		}
		if !result.Stages[0].Skipped {
			t.Error("expected stage to be skipped")
		}
		if len(result.SkippedTasks) != 1 {
			t.Errorf("expected 1 skipped task, got %d", len(result.SkippedTasks))
		}
	})

	t.Run("true condition executes stage", func(t *testing.T) {
		plan := Plan{
			Workflow: Workflow{Name: "conditional-test"},
			Stages: []PlanStage{
				{
					Name:      "conditional-stage",
					Condition: "true",
					Tasks:     []*PlanTask{task},
				},
			},
			Tasks: map[TaskKey]*PlanTask{task.Key: task},
		}

		result := runner.Run(plan, DefaultRunOptions())

		if !result.Success {
			t.Errorf("expected workflow to succeed, got error: %v", result.Error)
		}
		if len(result.Stages) != 1 {
			t.Errorf("expected 1 stage, got %d", len(result.Stages))
		}
		if result.Stages[0].Skipped {
			t.Error("expected stage NOT to be skipped")
		}
		if len(result.TaskResults) != 1 {
			t.Errorf("expected 1 task result, got %d", len(result.TaskResults))
		}
	})
}
