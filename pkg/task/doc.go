// Package task provides a task/target execution engine for Morphir.
//
// The task engine supports:
//   - Intrinsic actions (internal Morphir pipeline steps)
//   - External command execution (future: with sandboxing)
//   - Task dependencies with automatic resolution
//   - Pre/post hooks for task lifecycle management
//   - Diamond dependency handling (tasks run only once)
//   - JSON-serializable task outputs
//
// # Task Configuration
//
// Tasks are configured via morphir.toml (see docs/task-target-schema.md).
// Each task has:
//   - kind: "intrinsic" or "command"
//   - action: intrinsic action name (for kind=intrinsic)
//   - cmd: command array (for kind=command)
//   - depends_on: dependency task names
//   - pre: pre-hook task names
//   - post: post-hook task names
//   - inputs: input globs for caching
//   - outputs: output globs
//   - params: task parameters
//   - env: environment variables
//   - mounts: mount permissions (ro/rw)
//
// # Execution Model
//
// Tasks are executed in this order:
//  1. Resolve and execute all dependencies (depends_on)
//  2. Execute all pre hooks
//  3. Execute the main task
//  4. Execute all post hooks
//
// Execution stops immediately on the first error, but diagnostics
// and artifacts are preserved for reporting.
//
// # Example Usage
//
//	registry := task.NewTaskRegistry()
//
//	// Register an intrinsic action
//	registry.Register("morphir.validate", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
//	    // Validation logic
//	    return validationResult, pipeline.StepResult{
//	        Diagnostics: diagnostics,
//	    }
//	})
//
//	// Define tasks
//	tasks := map[string]task.Task{
//	    "validate": {
//	        Name: "validate",
//	        Config: task.TaskConfig{
//	            Kind:   task.TaskKindIntrinsic,
//	            Action: "morphir.validate",
//	            Inputs: []vfs.Glob{vfs.MustGlob("workspace:/src/**/*.elm")},
//	        },
//	    },
//	}
//
//	// Execute a task
//	executor := task.NewExecutor(registry, tasks)
//	result, err := executor.Execute(ctx, "validate")
//
// # Future Enhancements
//
// - External command execution with VFS-based sandboxing
// - Caching based on input/output globs
// - Parallel task execution where dependencies allow
// - Task timeouts and retries
package task
