package pipeline

// Step is a pure transformation with a stable name and description.
type Step[In, Out any] struct {
	Name        string
	Description string
	Run         func(Context, In) (Out, StepResult)
}

// NewStep constructs a new pipeline step.
func NewStep[In, Out any](name, description string, run func(Context, In) (Out, StepResult)) Step[In, Out] {
	return Step[In, Out]{
		Name:        name,
		Description: description,
		Run:         run,
	}
}

// Execute runs the step with the given context and input.
func (s Step[In, Out]) Execute(ctx Context, in In) (Out, StepResult) {
	return s.Run(ctx, in)
}
