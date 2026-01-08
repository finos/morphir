package task

import (
	"errors"
	"fmt"

	"github.com/finos/morphir/pkg/pipeline"
)

// Executor runs tasks with dependency resolution and hooks.
type Executor struct {
	registry *TaskRegistry
	tasks    map[string]Task
}

// NewExecutor creates a new task executor.
func NewExecutor(registry *TaskRegistry, tasks map[string]Task) *Executor {
	return &Executor{
		registry: registry,
		tasks:    tasks,
	}
}

// Execute runs a task and its dependencies.
func (e *Executor) Execute(ctx pipeline.Context, taskName string) (TaskResult, error) {
	task, ok := e.tasks[taskName]
	if !ok {
		return TaskResult{}, &TaskError{
			TaskName: taskName,
			Message:  "task not found",
		}
	}

	// Resolve and execute dependencies
	var allDeps []string
	if err := e.executeDependencies(ctx, task.Config.DependsOn(), &allDeps); err != nil {
		return TaskResult{
			Name:         taskName,
			Dependencies: allDeps,
			Err:          err,
		}, err
	}

	// Execute pre hooks
	if err := e.executeHooks(ctx, task.Config.Pre(), &allDeps); err != nil {
		return TaskResult{
			Name:         taskName,
			Dependencies: allDeps,
			Err:          err,
		}, err
	}

	// Execute the main task
	result, err := e.executeTask(ctx, task)
	result.Name = taskName

	if err != nil {
		result.Dependencies = allDeps
		return result, err
	}

	// Execute post hooks
	if err := e.executeHooks(ctx, task.Config.Post(), &allDeps); err != nil {
		result.Dependencies = allDeps
		result.Err = err
		return result, err
	}

	// Update dependencies after all hooks have run
	result.Dependencies = allDeps

	return result, nil
}

func (e *Executor) executeDependencies(ctx pipeline.Context, deps []string, executed *[]string) error {
	for _, dep := range deps {
		if err := e.executeTaskChain(ctx, dep, executed); err != nil {
			return err
		}
	}
	return nil
}

func (e *Executor) executeHooks(ctx pipeline.Context, hooks []string, executed *[]string) error {
	for _, hook := range hooks {
		if err := e.executeTaskChain(ctx, hook, executed); err != nil {
			return err
		}
	}
	return nil
}

func (e *Executor) executeTaskChain(ctx pipeline.Context, taskName string, executed *[]string) error {
	task, ok := e.tasks[taskName]
	if !ok {
		return &TaskError{
			TaskName: taskName,
			Message:  "task not found",
		}
	}

	// Check if this task was already executed (skip if already done)
	for _, exec := range *executed {
		if exec == taskName {
			return nil // Already executed, skip
		}
	}

	// Mark as being executed to detect circular dependencies
	*executed = append(*executed, taskName)

	// Execute dependencies first
	if err := e.executeDependencies(ctx, task.Config.DependsOn(), executed); err != nil {
		return err
	}

	// Execute pre hooks
	if err := e.executeHooks(ctx, task.Config.Pre(), executed); err != nil {
		return err
	}

	// Execute the task
	_, err := e.executeTask(ctx, task)
	if err != nil {
		return err
	}

	// Execute post hooks
	if err := e.executeHooks(ctx, task.Config.Post(), executed); err != nil {
		return err
	}

	return nil
}

func (e *Executor) executeTask(ctx pipeline.Context, task Task) (TaskResult, error) {
	switch cfg := task.Config.(type) {
	case IntrinsicTaskConfig:
		return e.executeIntrinsic(ctx, task.Name, cfg)
	case CommandTaskConfig:
		return e.executeCommand(ctx, task.Name, cfg)
	default:
		return TaskResult{}, &TaskError{
			TaskName: task.Name,
			Message:  fmt.Sprintf("unknown task config type: %T", cfg),
		}
	}
}

func (e *Executor) executeIntrinsic(ctx pipeline.Context, name string, cfg IntrinsicTaskConfig) (TaskResult, error) {
	action, ok := e.registry.Get(cfg.Action())
	if !ok {
		return TaskResult{}, &TaskError{
			TaskName: name,
			Message:  fmt.Sprintf("intrinsic action not found: %s", cfg.Action()),
		}
	}

	output, stepResult := action(ctx, cfg.Params())

	if stepResult.Err != nil {
		return TaskResult{
			Output:      output,
			Diagnostics: stepResult.Diagnostics,
			Artifacts:   stepResult.Artifacts,
			Err:         stepResult.Err,
		}, stepResult.Err
	}

	return TaskResult{
		Output:      output,
		Diagnostics: stepResult.Diagnostics,
		Artifacts:   stepResult.Artifacts,
	}, nil
}

// executeCommand is now implemented in command.go

// TaskError represents an error during task execution.
type TaskError struct {
	TaskName string
	Message  string
	Cause    error
}

func (e *TaskError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("task %s: %s: %v", e.TaskName, e.Message, e.Cause)
	}
	return fmt.Sprintf("task %s: %s", e.TaskName, e.Message)
}

func (e *TaskError) Unwrap() error {
	return e.Cause
}

// IsTaskNotFound checks if the error is a task not found error.
func IsTaskNotFound(err error) bool {
	var taskErr *TaskError
	if errors.As(err, &taskErr) {
		return taskErr.Message == "task not found"
	}
	return false
}
