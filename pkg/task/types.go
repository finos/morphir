package task

import (
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// TaskConfig is the sealed interface for task configurations.
// Use type assertions to access type-specific fields:
//
//	switch cfg := task.Config.(type) {
//	case IntrinsicTaskConfig:
//	    action := cfg.Action()
//	case CommandTaskConfig:
//	    cmd := cfg.Cmd()
//	}
type TaskConfig interface {
	DependsOn() []string
	Pre() []string
	Post() []string
	Inputs() []vfs.Glob
	Outputs() []vfs.Glob
	Params() map[string]any
	Env() map[string]string
	Mounts() map[string]string
	isTaskConfig() // unexported method seals the interface
}

// taskConfigCommon contains fields shared by all task config types.
type taskConfigCommon struct {
	dependsOn []string
	pre       []string
	post      []string
	inputs    []vfs.Glob
	outputs   []vfs.Glob
	params    map[string]any
	env       map[string]string
	mounts    map[string]string
}

// DependsOn returns the task dependencies.
func (c taskConfigCommon) DependsOn() []string {
	if len(c.dependsOn) == 0 {
		return nil
	}
	result := make([]string, len(c.dependsOn))
	copy(result, c.dependsOn)
	return result
}

// Pre returns the pre-hooks.
func (c taskConfigCommon) Pre() []string {
	if len(c.pre) == 0 {
		return nil
	}
	result := make([]string, len(c.pre))
	copy(result, c.pre)
	return result
}

// Post returns the post-hooks.
func (c taskConfigCommon) Post() []string {
	if len(c.post) == 0 {
		return nil
	}
	result := make([]string, len(c.post))
	copy(result, c.post)
	return result
}

// Inputs returns the input globs.
func (c taskConfigCommon) Inputs() []vfs.Glob {
	if len(c.inputs) == 0 {
		return nil
	}
	result := make([]vfs.Glob, len(c.inputs))
	copy(result, c.inputs)
	return result
}

// Outputs returns the output globs.
func (c taskConfigCommon) Outputs() []vfs.Glob {
	if len(c.outputs) == 0 {
		return nil
	}
	result := make([]vfs.Glob, len(c.outputs))
	copy(result, c.outputs)
	return result
}

// Params returns the task parameters.
func (c taskConfigCommon) Params() map[string]any {
	if len(c.params) == 0 {
		return nil
	}
	result := make(map[string]any, len(c.params))
	for k, v := range c.params {
		result[k] = v
	}
	return result
}

// Env returns the environment variables.
func (c taskConfigCommon) Env() map[string]string {
	if len(c.env) == 0 {
		return nil
	}
	result := make(map[string]string, len(c.env))
	for k, v := range c.env {
		result[k] = v
	}
	return result
}

// Mounts returns the mount permissions.
func (c taskConfigCommon) Mounts() map[string]string {
	if len(c.mounts) == 0 {
		return nil
	}
	result := make(map[string]string, len(c.mounts))
	for k, v := range c.mounts {
		result[k] = v
	}
	return result
}

// IntrinsicTaskConfig represents an intrinsic task configuration.
type IntrinsicTaskConfig struct {
	taskConfigCommon
	action string
}

func (IntrinsicTaskConfig) isTaskConfig() {}

// Action returns the intrinsic action identifier.
func (c IntrinsicTaskConfig) Action() string {
	return c.action
}

// CommandTaskConfig represents a command task configuration.
type CommandTaskConfig struct {
	taskConfigCommon
	cmd []string
}

func (CommandTaskConfig) isTaskConfig() {}

// Cmd returns the command and arguments.
func (c CommandTaskConfig) Cmd() []string {
	if len(c.cmd) == 0 {
		return nil
	}
	result := make([]string, len(c.cmd))
	copy(result, c.cmd)
	return result
}

// TaskResult represents the output of a task execution.
type TaskResult struct {
	Name         string
	Output       any                   // JSON-serializable task output
	Diagnostics  []pipeline.Diagnostic // Diagnostics from the task
	Artifacts    []pipeline.Artifact   // Artifacts produced
	Dependencies []string              // Actual dependencies run
	Err          error                 // Error if task failed
}

// Task represents an executable task.
type Task struct {
	Name   string
	Config TaskConfig
}

// NewIntrinsicTask creates a new intrinsic task.
func NewIntrinsicTask(name, action string, opts ...TaskOption) Task {
	cfg := IntrinsicTaskConfig{action: action}
	for _, opt := range opts {
		opt(&cfg.taskConfigCommon)
	}
	return Task{Name: name, Config: cfg}
}

// NewCommandTask creates a new command task.
func NewCommandTask(name string, cmd []string, opts ...TaskOption) Task {
	cfg := CommandTaskConfig{cmd: cmd}
	for _, opt := range opts {
		opt(&cfg.taskConfigCommon)
	}
	return Task{Name: name, Config: cfg}
}

// TaskOption configures common task fields.
type TaskOption func(*taskConfigCommon)

// WithDependsOn sets task dependencies.
func WithDependsOn(deps []string) TaskOption {
	return func(c *taskConfigCommon) { c.dependsOn = deps }
}

// WithPre sets pre-hooks.
func WithPre(pre []string) TaskOption {
	return func(c *taskConfigCommon) { c.pre = pre }
}

// WithPost sets post-hooks.
func WithPost(post []string) TaskOption {
	return func(c *taskConfigCommon) { c.post = post }
}

// WithInputs sets input globs.
func WithInputs(inputs []vfs.Glob) TaskOption {
	return func(c *taskConfigCommon) { c.inputs = inputs }
}

// WithOutputs sets output globs.
func WithOutputs(outputs []vfs.Glob) TaskOption {
	return func(c *taskConfigCommon) { c.outputs = outputs }
}

// WithParams sets task parameters.
func WithParams(params map[string]any) TaskOption {
	return func(c *taskConfigCommon) { c.params = params }
}

// WithEnv sets environment variables.
func WithEnv(env map[string]string) TaskOption {
	return func(c *taskConfigCommon) { c.env = env }
}

// WithMounts sets mount permissions.
func WithMounts(mounts map[string]string) TaskOption {
	return func(c *taskConfigCommon) { c.mounts = mounts }
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
