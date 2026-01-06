package pipeline

import "time"

// Package pipeline provides processing pipelines for Morphir IR transformations.
//
// This package follows functional programming principles:
// - Immutable data structures
// - Pure functions where possible
// - Clear separation of concerns
// - Functional composition patterns

// Pipeline is a sequence of steps that transforms In to Out.
type Pipeline[In, Out any] struct {
	Name        string
	Description string
	run         func(Context, In) (Out, PipelineResult, error)
}

// NewPipeline constructs a new pipeline from a single step.
func NewPipeline[In, Out any](name, description string, step Step[In, Out]) *Pipeline[In, Out] {
	return &Pipeline[In, Out]{
		Name:        name,
		Description: description,
		run: func(ctx Context, in In) (Out, PipelineResult, error) {
			started := time.Now()
			out, stepResult := step.Run(ctx, in)
			finished := time.Now()

			execution := StepExecution{
				Name:        step.Name,
				Description: step.Description,
				Started:     started,
				Finished:    finished,
				Duration:    finished.Sub(started),
				Result:      stepResult,
			}

			result := PipelineResult{
				Diagnostics: stepResult.Diagnostics,
				Artifacts:   stepResult.Artifacts,
				Steps:       []StepExecution{execution},
			}

			if stepResult.Err != nil {
				var zero Out
				return zero, result, stepResult.Err
			}

			return out, result, nil
		},
	}
}

// Then chains a step onto this pipeline, creating a new pipeline.
// The output type of the current pipeline must match the input type of the next step.
func Then[In, Mid, Out any](p *Pipeline[In, Mid], step Step[Mid, Out]) *Pipeline[In, Out] {
	return &Pipeline[In, Out]{
		Name:        p.Name,
		Description: p.Description,
		run: func(ctx Context, in In) (Out, PipelineResult, error) {
			var zero Out

			// Run the first pipeline
			mid, result1, err := p.run(ctx, in)
			if err != nil {
				return zero, result1, err
			}

			// Run the next step
			started := time.Now()
			out, stepResult := step.Run(ctx, mid)
			finished := time.Now()

			execution := StepExecution{
				Name:        step.Name,
				Description: step.Description,
				Started:     started,
				Finished:    finished,
				Duration:    finished.Sub(started),
				Result:      stepResult,
			}

			// Combine results
			result := PipelineResult{
				Diagnostics: append(result1.Diagnostics, stepResult.Diagnostics...),
				Artifacts:   append(result1.Artifacts, stepResult.Artifacts...),
				Steps:       append(result1.Steps, execution),
			}

			if stepResult.Err != nil {
				return zero, result, stepResult.Err
			}

			return out, result, nil
		},
	}
}

// Run executes the pipeline with the given context and input.
// Execution stops on the first error, but diagnostics and artifacts are preserved.
func (p *Pipeline[In, Out]) Run(ctx Context, in In) (Out, PipelineResult, error) {
	return p.run(ctx, in)
}

// PipelineError represents an error during pipeline execution.
type PipelineError struct {
	Message  string
	Pipeline string
	Step     string
	Cause    error
}

func (e *PipelineError) Error() string {
	if e.Step != "" {
		return "pipeline " + e.Pipeline + " step " + e.Step + ": " + e.Message
	}
	return "pipeline " + e.Pipeline + ": " + e.Message
}

func (e *PipelineError) Unwrap() error {
	return e.Cause
}
