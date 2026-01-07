package task

import (
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// TaskKind identifies the type of task execution.
type TaskKind string

const (
	TaskKindIntrinsic TaskKind = "intrinsic" // Internal Morphir pipeline step
	TaskKindCommand   TaskKind = "command"   // External command execution
)

// TaskConfig defines the configuration for a task in morphir.toml.
type TaskConfig struct {
	Kind      TaskKind
	Action    string            // For intrinsic tasks
	Cmd       []string          // For command tasks
	DependsOn []string          // Task dependencies
	Pre       []string          // Tasks to run before this task
	Post      []string          // Tasks to run after this task
	Inputs    []vfs.Glob        // Input globs for caching
	Outputs   []vfs.Glob        // Output globs
	Params    map[string]any    // Task parameters
	Env       map[string]string // Environment variables
	Mounts    map[string]string // Mount permissions (ro/rw)
}

// TaskResult represents the output of a task execution.
type TaskResult struct {
	Name         string
	Output       any                       // JSON-serializable task output
	Diagnostics  []pipeline.Diagnostic     // Diagnostics from the task
	Artifacts    []pipeline.Artifact       // Artifacts produced
	Dependencies []string                  // Actual dependencies run
	Err          error                     // Error if task failed
}

// Task represents an executable task.
type Task struct {
	Name   string
	Config TaskConfig
}

// TaskRegistry holds registered intrinsic actions.
type TaskRegistry struct {
	actions map[string]IntrinsicAction
}

// IntrinsicAction is a function that implements an intrinsic task action.
type IntrinsicAction func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult)

// NewTaskRegistry creates a new task registry.
func NewTaskRegistry() *TaskRegistry {
	return &TaskRegistry{
		actions: make(map[string]IntrinsicAction),
	}
}

// Register registers an intrinsic action.
func (r *TaskRegistry) Register(name string, action IntrinsicAction) {
	r.actions[name] = action
}

// Get retrieves an intrinsic action by name.
func (r *TaskRegistry) Get(name string) (IntrinsicAction, bool) {
	action, ok := r.actions[name]
	return action, ok
}
