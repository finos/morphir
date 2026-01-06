package adapter

import (
	"fmt"

	"go.bytecodealliance.org/wit"
)

// AdapterError represents an error that occurred during WIT adaptation.
type AdapterError struct {
	Context string // What was being adapted (e.g., "package", "interface", "type")
	Name    string // Name of the item being adapted
	Cause   error  // Underlying error
}

func (e *AdapterError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("failed to adapt %s %q: %v", e.Context, e.Name, e.Cause)
	}
	return fmt.Sprintf("failed to adapt %s %q", e.Context, e.Name)
}

func (e *AdapterError) Unwrap() error {
	return e.Cause
}

// newAdapterError creates a new adapter error.
func newAdapterError(context, name string, cause error) *AdapterError {
	return &AdapterError{
		Context: context,
		Name:    name,
		Cause:   cause,
	}
}

// ValidationError represents a validation error for unsupported or invalid WIT constructs.
type ValidationError struct {
	Message string
	Item    string
}

func (e *ValidationError) Error() string {
	if e.Item != "" {
		return fmt.Sprintf("validation error for %s: %s", e.Item, e.Message)
	}
	return fmt.Sprintf("validation error: %s", e.Message)
}

// newValidationError creates a new validation error.
func newValidationError(item, message string) *ValidationError {
	return &ValidationError{
		Item:    item,
		Message: message,
	}
}

// AdapterContext holds context information for the adaptation process.
type AdapterContext struct {
	// Resolve is the complete WIT resolution containing all packages and types
	Resolve *wit.Resolve

	// Strict mode causes the adapter to fail on unsupported features
	// rather than skip them with warnings
	Strict bool

	// Warnings collects non-fatal issues encountered during adaptation
	Warnings []string
}

// NewAdapterContext creates a new adapter context.
func NewAdapterContext(resolve *wit.Resolve) *AdapterContext {
	return &AdapterContext{
		Resolve:  resolve,
		Warnings: make([]string, 0),
	}
}

// AddWarning adds a warning to the context.
func (ctx *AdapterContext) AddWarning(format string, args ...interface{}) {
	ctx.Warnings = append(ctx.Warnings, fmt.Sprintf(format, args...))
}

// WithStrict returns a new context with strict mode enabled.
func (ctx *AdapterContext) WithStrict() *AdapterContext {
	newCtx := *ctx
	newCtx.Strict = true
	return &newCtx
}
