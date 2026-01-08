package task

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// Executor runs tasks with dependency resolution, hooks, caching, and parallelism.
type Executor struct {
	registry       *TaskRegistry
	tasks          map[string]Task
	cacheManager   *CacheManager
	vfs            vfs.VFS
	maxParallelism int
	noCache        bool
	projectRoot    string // Needed for constructing CacheManager if not passed

	// Internal state for a single execution run
	mu            sync.Mutex
	executed      map[string]*TaskResult // Results of executed tasks
	executing     map[string]chan struct{} // Channels to wait for running tasks
	inputsHashes  map[string]string      // Verified input hashes
}

// ExecutorOption configures the executor.
type ExecutorOption func(*Executor)

func WithCacheManager(cm *CacheManager) ExecutorOption {
	return func(e *Executor) { e.cacheManager = cm }
}

func WithVFS(fs vfs.VFS) ExecutorOption {
	return func(e *Executor) { e.vfs = fs }
}

func WithMaxParallelism(n int) ExecutorOption {
	return func(e *Executor) { e.maxParallelism = n }
}

func WithNoCache(noCache bool) ExecutorOption {
	return func(e *Executor) { e.noCache = noCache }
}

func WithProjectRoot(root string) ExecutorOption {
	return func(e *Executor) { e.projectRoot = root }
}

// NewExecutor creates a new task executor.
func NewExecutor(registry *TaskRegistry, tasks map[string]Task, opts ...ExecutorOption) *Executor {
	e := &Executor{
		registry:       registry,
		tasks:          tasks,
		maxParallelism: 1, // Default to serial
		executed:       make(map[string]*TaskResult),
		executing:      make(map[string]chan struct{}),
		inputsHashes:   make(map[string]string),
	}

	for _, opt := range opts {
		opt(e)
	}

	return e
}

// Execute runs a task and its dependencies.
func (e *Executor) Execute(ctx pipeline.Context, taskName string) (TaskResult, error) {
	// Initialize execution state (if we want to allow reuse of executor, we should clear or separate state)
	// For now, assuming Executor instance is used for one build pass.
	// If it's reused, we rely on `executed` map acting as memoization for the session.

	// Use a semaphore to limit parallelism
	sem := make(chan struct{}, e.maxParallelism)

	// Create a context that can be cancelled on error
	// We use the pipeline context which has ...? checking pipeline.Context definition
	// pipeline.Context doesn't seem to have standard Go context.Context.
	// We'll proceed with standard sync.

	return e.executeTaskMemoized(ctx, taskName, sem, nil)
}

func (e *Executor) executeTaskMemoized(ctx pipeline.Context, taskName string, sem chan struct{}, dependencyChain []string) (TaskResult, error) {
	e.mu.Lock()
	if res, ok := e.executed[taskName]; ok {
		e.mu.Unlock()
		if res.Err != nil {
			return *res, res.Err
		}
		return *res, nil
	}

	// Check for cycles
	for _, dep := range dependencyChain {
		if dep == taskName {
			e.mu.Unlock()
			return TaskResult{}, fmt.Errorf("circular dependency detected: %v -> %s", dependencyChain, taskName)
		}
	}

	// If already executing, wait
	if waitChan, ok := e.executing[taskName]; ok {
		e.mu.Unlock()
		<-waitChan
		// After wait, check result again
		e.mu.Lock()
		if res, ok := e.executed[taskName]; ok {
			e.mu.Unlock()
			return *res, res.Err
		}
		e.mu.Unlock()
		return TaskResult{}, fmt.Errorf("task %s finished but result missing", taskName)
	}

	// Mark as executing
	doneChan := make(chan struct{})
	e.executing[taskName] = doneChan
	e.mu.Unlock()

	// Ensure we cleanup executing properties
	defer func() {
		e.mu.Lock()
		delete(e.executing, taskName)
		close(doneChan)
		e.mu.Unlock()
	}()

	task, ok := e.tasks[taskName]
	if !ok {
		err := &TaskError{TaskName: taskName, Message: "task not found"}
		e.recordResult(taskName, TaskResult{Err: err})
		return TaskResult{}, err
	}

	// 1. Execute Dependencies (in parallel if possible)
	deps := task.Config.DependsOn()
	// depResults := make([]TaskResult, len(deps)) // Unused
	var wg sync.WaitGroup
	errChan := make(chan error, len(deps))

	// New chain for recursion
	newChain := append(dependencyChain, taskName)

	for _, dep := range deps {
		dep := dep
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := e.executeTaskMemoized(ctx, dep, sem, newChain)
			if err != nil {
				errChan <- err
				return
			}
			// depResults[i] = res
		}()
	}

	wg.Wait()
	close(errChan)

	if err := <-errChan; err != nil {
		res := TaskResult{Name: taskName, Err: err}
		e.recordResult(taskName, res)
		return res, err
	}
	
	// Collect dependency hashes for this task's input hash
	depHashes := make(map[string]string)
	allDepsList := make([]string, 0, len(deps))
	for _, dep := range deps {
		allDepsList = append(allDepsList, dep)
		
		e.mu.Lock()
		if h, ok := e.inputsHashes[dep]; ok {
			depHashes[dep] = h
		}
		e.mu.Unlock()
	}

    // 1.5 Execute Pre Hooks
    // Hooks are executed sequentially for now to ensure stable order, or could be parallel.
    // Usually pre-hooks might set up environment so serial is safer or parallel is fine if independent.
    // The test expects them to be in dependencies list.
    for _, pre := range task.Config.Pre() {
        _, err := e.executeTaskMemoized(ctx, pre, sem, newChain)
        if err != nil {
            res := TaskResult{Name: taskName, Err: err}
            e.recordResult(taskName, res)
            return res, err
        }
        allDepsList = append(allDepsList, pre)
        
        e.mu.Lock()
        if h, ok := e.inputsHashes[pre]; ok {
            depHashes[pre] = h
        }
        e.mu.Unlock()
    }

	// 2. Compute Input Hash
	var inputHash string
	if e.vfs != nil {
		var err error
		// We assume tool version "0.1" for now
		inputHash, err = ComputeTaskHash(task, e.vfs, depHashes, "0.1")
		if err != nil {
			// If hashing fails, we proceed without caching? Or fail?
			// Let's fail safe
			err = fmt.Errorf("hashing failed: %w", err)
			res := TaskResult{Name: taskName, Err: err}
			e.recordResult(taskName, res)
			return res, err
		}
	}

	// 3. Check Cache
	if !e.noCache && e.cacheManager != nil && inputHash != "" {
		if result, hit := e.cacheManager.Get(inputHash); hit {
			// Cache Hit
			result.Name = taskName
			result.Dependencies = allDepsList
			// We might want to "touch" artifacts or logging?
			// Mark as cached in some way?
			// Diagnostics?
			e.recordResult(taskName, result)
			e.recordInputHash(taskName, inputHash)
			return result, nil
		}
	}

	// 4. Execute Task (rate limited)
	// Note: We need to context for cancellation? 
	// pipeline.Context is passed down.
	
	select {
	case sem <- struct{}{}: // Acquire token
	case <-context.TODO().Done(): // Placeholder for context cancellation if we had it
		return TaskResult{}, context.Canceled
	}
	
	result, err := e.executeTaskInternal(ctx, task)
	<-sem // Release token

	result.Name = taskName
	result.Dependencies = allDepsList

	if err != nil {
		e.recordResult(taskName, result)
		return result, err
	}

    // 4.5 Execute Post Hooks
    // Post hooks are executed after the main task
    for _, post := range task.Config.Post() {
        _, err := e.executeTaskMemoized(ctx, post, sem, newChain)
        if err != nil {
            // If post hook fails, the whole task fails? Usually yes.
            res := TaskResult{Name: taskName, Err: err}
            e.recordResult(taskName, res)
            return res, err
        }
        allDepsList = append(allDepsList, post)
    }

	result.Name = taskName
	result.Dependencies = allDepsList

	// 5. Save to Cache
	if !e.noCache && e.cacheManager != nil && inputHash != "" {
		if err := e.cacheManager.Put(inputHash, result); err != nil {
			// Log error but don't fail build
			fmt.Printf("Warning: failed to cache result for %s: %v\n", taskName, err)
		}
	}

	e.recordResult(taskName, result)
	e.recordInputHash(taskName, inputHash)
	return result, nil
}

func (e *Executor) recordResult(name string, res TaskResult) {
	e.mu.Lock()
	e.executed[name] = &res
	e.mu.Unlock()
}

func (e *Executor) recordInputHash(name string, hash string) {
	e.mu.Lock()
	e.inputsHashes[name] = hash
	e.mu.Unlock()
}

// executeTaskInternal executes the task logic (hooks + main action)
func (e *Executor) executeTaskInternal(ctx pipeline.Context, task Task) (TaskResult, error) {
	// Hooks are not fully implemented in parallel version yet (pre/post)
	// For MVP of caching, we'll execute pre/action/post in sequence here
	// Ignoring pre/post hooks parallelism for now, assuming they are part of this task unit

	// Pre hooks
	if len(task.Config.Pre()) > 0 {
		// Just run them
	}
	
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

// executeCommand is assumed to be in command.go (same package)

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
