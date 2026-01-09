package toolchain

import (
	"context"
	"fmt"
	"sync"
	"time"
)

// WorkflowResult captures the result of a complete workflow execution.
type WorkflowResult struct {
	// Workflow is the workflow that was executed
	Workflow Workflow

	// Plan is the execution plan that was used
	Plan Plan

	// Stages are the results from each stage
	Stages []StageResult

	// TaskResults maps task keys to their results
	TaskResults map[TaskKey]TaskResult

	// StartTime is when the workflow started
	StartTime time.Time

	// EndTime is when the workflow finished
	EndTime time.Time

	// Duration is the total workflow execution time
	Duration time.Duration

	// Success indicates whether all tasks succeeded
	Success bool

	// Error is set if the workflow failed
	Error error

	// FailedTasks contains keys of tasks that failed
	FailedTasks []TaskKey

	// SkippedTasks contains keys of tasks that were skipped
	SkippedTasks []TaskKey
}

// StageResult captures the result of a single stage execution.
type StageResult struct {
	// Name is the stage name
	Name string

	// Index is the stage index in the plan
	Index int

	// Tasks are the task results for this stage
	Tasks []TaskResult

	// StartTime is when the stage started
	StartTime time.Time

	// EndTime is when the stage finished
	EndTime time.Time

	// Duration is the stage execution time
	Duration time.Duration

	// Success indicates whether all tasks in this stage succeeded
	Success bool

	// Skipped indicates whether this stage was skipped
	Skipped bool

	// SkipReason explains why the stage was skipped
	SkipReason string
}

// RunOptions configures workflow execution.
type RunOptions struct {
	// DryRun if true, validates the plan but doesn't execute tasks
	DryRun bool

	// StopOnError if true, stops execution on first error (default: true)
	StopOnError bool

	// MaxParallel limits parallel task execution (0 = unlimited)
	MaxParallel int

	// Timeout is the overall workflow timeout (0 = no timeout)
	Timeout time.Duration

	// Progress is called to report execution progress
	Progress ProgressCallback

	// Context is the execution context for cancellation
	Context context.Context
}

// DefaultRunOptions returns the default run options.
func DefaultRunOptions() RunOptions {
	return RunOptions{
		DryRun:      false,
		StopOnError: true,
		MaxParallel: 0,
		Timeout:     0,
		Progress:    nil,
		Context:     context.Background(),
	}
}

// ProgressCallback is called to report workflow execution progress.
type ProgressCallback func(event ProgressEvent)

// ProgressEvent represents a progress update during workflow execution.
type ProgressEvent struct {
	// Type is the event type
	Type ProgressEventType

	// Timestamp is when the event occurred
	Timestamp time.Time

	// Stage is the current stage (if applicable)
	Stage *PlanStage

	// StageIndex is the current stage index
	StageIndex int

	// Task is the current task (if applicable)
	Task *PlanTask

	// TaskResult is the task result (for TaskCompleted events)
	TaskResult *TaskResult

	// Message is an optional human-readable message
	Message string

	// Error is set for error events
	Error error
}

// ProgressEventType indicates the type of progress event.
type ProgressEventType string

const (
	// ProgressWorkflowStarted indicates the workflow has started
	ProgressWorkflowStarted ProgressEventType = "workflow_started"

	// ProgressWorkflowCompleted indicates the workflow has completed
	ProgressWorkflowCompleted ProgressEventType = "workflow_completed"

	// ProgressStageStarted indicates a stage has started
	ProgressStageStarted ProgressEventType = "stage_started"

	// ProgressStageCompleted indicates a stage has completed
	ProgressStageCompleted ProgressEventType = "stage_completed"

	// ProgressStageSkipped indicates a stage was skipped
	ProgressStageSkipped ProgressEventType = "stage_skipped"

	// ProgressTaskStarted indicates a task has started
	ProgressTaskStarted ProgressEventType = "task_started"

	// ProgressTaskCompleted indicates a task has completed
	ProgressTaskCompleted ProgressEventType = "task_completed"

	// ProgressTaskSkipped indicates a task was skipped
	ProgressTaskSkipped ProgressEventType = "task_skipped"

	// ProgressError indicates an error occurred
	ProgressError ProgressEventType = "error"
)

// WorkflowRunner executes workflow plans.
type WorkflowRunner struct {
	executor  *Executor
	outputDir *OutputDirStructure
}

// NewWorkflowRunner creates a new workflow runner.
func NewWorkflowRunner(executor *Executor, outputDir *OutputDirStructure) *WorkflowRunner {
	return &WorkflowRunner{
		executor:  executor,
		outputDir: outputDir,
	}
}

// Run executes a workflow plan and returns the aggregated result.
func (r *WorkflowRunner) Run(plan Plan, opts RunOptions) WorkflowResult {
	result := WorkflowResult{
		Workflow:    plan.Workflow,
		Plan:        plan,
		Stages:      make([]StageResult, 0, len(plan.Stages)),
		TaskResults: make(map[TaskKey]TaskResult),
		StartTime:   time.Now(),
		Success:     true,
	}

	// Set up context with timeout if specified
	ctx := opts.Context
	if ctx == nil {
		ctx = context.Background()
	}
	if opts.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, opts.Timeout)
		defer cancel()
	}

	// Report workflow started
	r.reportProgress(opts.Progress, ProgressEvent{
		Type:      ProgressWorkflowStarted,
		Timestamp: result.StartTime,
		Message:   fmt.Sprintf("Starting workflow: %s", plan.Workflow.Name),
	})

	// Execute stages in order
stageLoop:
	for stageIndex, planStage := range plan.Stages {
		// Check for cancellation
		select {
		case <-ctx.Done():
			result.Error = ctx.Err()
			result.Success = false
			break stageLoop
		default:
		}

		if result.Error != nil {
			break
		}

		stageResult := r.executeStage(ctx, plan, planStage, stageIndex, opts, &result)
		result.Stages = append(result.Stages, stageResult)

		if !stageResult.Success && !stageResult.Skipped {
			result.Success = false
			if opts.StopOnError {
				result.Error = fmt.Errorf("stage %q failed", planStage.Name)
				break
			}
		}
	}

	result.EndTime = time.Now()
	result.Duration = result.EndTime.Sub(result.StartTime)

	// Collect failed and skipped tasks
	for key, taskResult := range result.TaskResults {
		if taskResult.Error != nil || !taskResult.Metadata.Success {
			result.FailedTasks = append(result.FailedTasks, key)
		}
	}

	// Report workflow completed
	r.reportProgress(opts.Progress, ProgressEvent{
		Type:      ProgressWorkflowCompleted,
		Timestamp: result.EndTime,
		Message:   fmt.Sprintf("Workflow %s completed in %s", plan.Workflow.Name, result.Duration),
	})

	return result
}

// executeStage executes a single stage and returns the result.
func (r *WorkflowRunner) executeStage(
	ctx context.Context,
	plan Plan,
	stage PlanStage,
	stageIndex int,
	opts RunOptions,
	workflowResult *WorkflowResult,
) StageResult {
	stageResult := StageResult{
		Name:      stage.Name,
		Index:     stageIndex,
		Tasks:     make([]TaskResult, 0, len(stage.Tasks)),
		StartTime: time.Now(),
		Success:   true,
	}

	// Check stage condition (placeholder for future implementation)
	if stage.Condition != "" {
		// TODO: Evaluate condition expression
		// For now, conditions are not evaluated
	}

	// Report stage started
	r.reportProgress(opts.Progress, ProgressEvent{
		Type:       ProgressStageStarted,
		Timestamp:  stageResult.StartTime,
		Stage:      &stage,
		StageIndex: stageIndex,
		Message:    fmt.Sprintf("Starting stage: %s", stage.Name),
	})

	// Check for skipped dependencies
	for _, task := range stage.Tasks {
		for _, dep := range task.DependsOn {
			if depResult, ok := workflowResult.TaskResults[dep]; ok {
				if depResult.Error != nil || !depResult.Metadata.Success {
					stageResult.Skipped = true
					stageResult.SkipReason = fmt.Sprintf("dependency %s failed", dep.String())
					break
				}
			}
		}
		if stageResult.Skipped {
			break
		}
	}

	if stageResult.Skipped {
		stageResult.EndTime = time.Now()
		stageResult.Duration = stageResult.EndTime.Sub(stageResult.StartTime)

		// Mark all tasks in this stage as skipped
		for _, task := range stage.Tasks {
			workflowResult.SkippedTasks = append(workflowResult.SkippedTasks, task.Key)
		}

		r.reportProgress(opts.Progress, ProgressEvent{
			Type:       ProgressStageSkipped,
			Timestamp:  stageResult.EndTime,
			Stage:      &stage,
			StageIndex: stageIndex,
			Message:    fmt.Sprintf("Stage %s skipped: %s", stage.Name, stageResult.SkipReason),
		})

		return stageResult
	}

	// Execute tasks (parallel or sequential)
	if stage.Parallel && len(stage.Tasks) > 1 && !opts.DryRun {
		stageResult.Tasks = r.executeTasksParallel(ctx, stage.Tasks, opts, workflowResult)
	} else {
		stageResult.Tasks = r.executeTasksSequential(ctx, stage.Tasks, opts, workflowResult)
	}

	// Check for failures
	for _, taskResult := range stageResult.Tasks {
		if taskResult.Error != nil || !taskResult.Metadata.Success {
			stageResult.Success = false
			break
		}
	}

	stageResult.EndTime = time.Now()
	stageResult.Duration = stageResult.EndTime.Sub(stageResult.StartTime)

	// Report stage completed
	r.reportProgress(opts.Progress, ProgressEvent{
		Type:       ProgressStageCompleted,
		Timestamp:  stageResult.EndTime,
		Stage:      &stage,
		StageIndex: stageIndex,
		Message:    fmt.Sprintf("Stage %s completed in %s", stage.Name, stageResult.Duration),
	})

	return stageResult
}

// executeTasksSequential executes tasks one at a time.
func (r *WorkflowRunner) executeTasksSequential(
	ctx context.Context,
	tasks []*PlanTask,
	opts RunOptions,
	workflowResult *WorkflowResult,
) []TaskResult {
	results := make([]TaskResult, 0, len(tasks))

	for _, task := range tasks {
		// Check for cancellation
		select {
		case <-ctx.Done():
			return results
		default:
		}

		taskResult := r.executeTask(ctx, task, opts)
		results = append(results, taskResult)
		workflowResult.TaskResults[task.Key] = taskResult

		if (taskResult.Error != nil || !taskResult.Metadata.Success) && opts.StopOnError {
			break
		}
	}

	return results
}

// executeTasksParallel executes tasks concurrently.
func (r *WorkflowRunner) executeTasksParallel(
	ctx context.Context,
	tasks []*PlanTask,
	opts RunOptions,
	workflowResult *WorkflowResult,
) []TaskResult {
	results := make([]TaskResult, len(tasks))
	var wg sync.WaitGroup
	var mu sync.Mutex

	// Create semaphore for max parallel limit
	var sem chan struct{}
	if opts.MaxParallel > 0 {
		sem = make(chan struct{}, opts.MaxParallel)
	}

	for i, task := range tasks {
		wg.Add(1)

		go func(idx int, t *PlanTask) {
			defer wg.Done()

			// Acquire semaphore if limited
			if sem != nil {
				select {
				case sem <- struct{}{}:
					defer func() { <-sem }()
				case <-ctx.Done():
					return
				}
			}

			// Check for cancellation
			select {
			case <-ctx.Done():
				return
			default:
			}

			taskResult := r.executeTask(ctx, t, opts)

			mu.Lock()
			results[idx] = taskResult
			workflowResult.TaskResults[t.Key] = taskResult
			mu.Unlock()
		}(i, task)
	}

	wg.Wait()
	return results
}

// executeTask executes a single task.
func (r *WorkflowRunner) executeTask(
	ctx context.Context,
	task *PlanTask,
	opts RunOptions,
) TaskResult {
	// Report task started
	r.reportProgress(opts.Progress, ProgressEvent{
		Type:      ProgressTaskStarted,
		Timestamp: time.Now(),
		Task:      task,
		Message:   fmt.Sprintf("Starting task: %s", task.Key.String()),
	})

	var result TaskResult

	if opts.DryRun {
		// In dry run mode, create a successful result without executing
		result = TaskResult{
			Metadata: TaskMetadata{
				ToolchainName: task.Toolchain,
				TaskName:      task.Task,
				StartTime:     time.Now(),
				EndTime:       time.Now(),
				Duration:      0,
				Success:       true,
			},
			Outputs:     make(map[string]any),
			Diagnostics: nil,
			Artifacts:   nil,
			Error:       nil,
		}
	} else {
		// Execute the actual task
		var err error
		result, err = r.executor.ExecuteTask(task.Toolchain, task.Task, task.Variant)
		if err != nil {
			result.Error = err
			result.Metadata.Success = false
		}
	}

	// Report task completed
	r.reportProgress(opts.Progress, ProgressEvent{
		Type:       ProgressTaskCompleted,
		Timestamp:  time.Now(),
		Task:       task,
		TaskResult: &result,
		Message:    fmt.Sprintf("Task %s completed (success=%v)", task.Key.String(), result.Metadata.Success),
	})

	return result
}

// reportProgress safely calls the progress callback.
func (r *WorkflowRunner) reportProgress(callback ProgressCallback, event ProgressEvent) {
	if callback != nil {
		callback(event)
	}
}

// Summary returns a human-readable summary of the workflow result.
func (r WorkflowResult) Summary() string {
	status := "SUCCESS"
	if !r.Success {
		status = "FAILED"
	}

	summary := fmt.Sprintf("Workflow: %s\nStatus: %s\nDuration: %s\n",
		r.Workflow.Name, status, r.Duration)

	summary += fmt.Sprintf("Tasks: %d total, %d failed, %d skipped\n",
		len(r.TaskResults), len(r.FailedTasks), len(r.SkippedTasks))

	if len(r.FailedTasks) > 0 {
		summary += "Failed tasks:\n"
		for _, key := range r.FailedTasks {
			summary += fmt.Sprintf("  - %s\n", key.String())
		}
	}

	return summary
}

// TaskCount returns the total number of tasks in the workflow.
func (r WorkflowResult) TaskCount() int {
	return len(r.TaskResults)
}

// SuccessfulTaskCount returns the number of successful tasks.
func (r WorkflowResult) SuccessfulTaskCount() int {
	return len(r.TaskResults) - len(r.FailedTasks) - len(r.SkippedTasks)
}
