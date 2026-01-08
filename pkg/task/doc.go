// Package task provides a task/target execution engine for Morphir.
//
// The task engine supports:
//   - Intrinsic actions (internal Morphir pipeline steps)
//   - External command execution
//   - Task dependencies with automatic resolution
//   - Pre/post hooks for task lifecycle management
//   - Diamond dependency handling (tasks run only once)
//   - JSON-serializable task outputs
//
// # Task Types
//
// Tasks use a typestate pattern where the task kind is encoded in the type:
//   - IntrinsicTaskConfig: Internal Morphir actions (validate, build, etc.)
//   - CommandTaskConfig: External command execution
//
// This design makes illegal states unrepresentable at compile time.
//
// # Task Configuration
//
// Tasks are configured via morphir.toml (see docs/task-target-schema.md).
// Each task has:
//   - For intrinsic tasks: action name (e.g., "morphir.validate")
//   - For command tasks: command array
//   - Common fields: depends_on, pre, post, inputs, outputs, params, env, mounts
//
// # Built-in Actions
//
// The package provides built-in intrinsic actions:
//   - morphir.validate: Validate morphir.ir.json against the schema
//   - morphir.build: Compile Morphir sources to IR (placeholder)
//   - morphir.test: Run tests (placeholder)
//   - morphir.clean: Remove build artifacts
//
// Use DefaultRegistry() to get a registry pre-populated with these actions.
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
//	// Use the default registry with built-in actions
//	registry := task.DefaultRegistry()
//
//	// Or create a custom registry and register actions
//	registry := task.NewTaskRegistry()
//	registry.Register("custom.action", func(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
//	    return result, pipeline.StepResult{}
//	})
//
//	// Define tasks using constructors
//	tasks := map[string]task.Task{
//	    "validate": task.NewIntrinsicTask("validate", task.ActionValidate,
//	        task.WithInputs([]vfs.Glob{vfs.MustGlob("workspace:/morphir.ir.json")}),
//	    ),
//	    "build": task.NewIntrinsicTask("build", task.ActionBuild,
//	        task.WithParams(map[string]any{"source": "src"}),
//	    ),
//	    "lint": task.NewCommandTask("lint", []string{"./scripts/lint.sh"},
//	        task.WithDependsOn([]string{"build"}),
//	    ),
//	}
//
//	// Execute a task
//	executor := task.NewExecutor(registry, tasks)
//	result, err := executor.Execute(ctx, "validate")
//
// # Future Enhancements
//
// - Caching based on input/output globs
// - Parallel task execution where dependencies allow
// - Task timeouts and retries
// - VFS-based sandboxing for commands
package task
