package config

import (
	"errors"
	"fmt"
)

// Sentinel errors for configuration operations.
var (
	// ErrNotFound indicates a configuration file was not found at the expected location.
	ErrNotFound = errors.New("config: not found")

	// ErrInvalidFormat indicates the configuration file has an invalid format.
	ErrInvalidFormat = errors.New("config: invalid format")

	// ErrMergeConflict indicates a conflict occurred while merging configuration layers.
	ErrMergeConflict = errors.New("config: merge conflict")
)

// LoadError represents an error that occurred while loading configuration.
// It wraps the underlying error and includes context about the source.
type LoadError struct {
	Source string // The configuration source that caused the error (e.g., file path, "env")
	Err    error  // The underlying error
}

// Error returns the error message.
func (e LoadError) Error() string {
	if e.Source == "" {
		return fmt.Sprintf("config: load error: %v", e.Err)
	}
	return fmt.Sprintf("config: load error from %s: %v", e.Source, e.Err)
}

// Unwrap returns the underlying error for use with errors.Is and errors.As.
func (e LoadError) Unwrap() error {
	return e.Err
}

// ParseError represents an error that occurred while parsing configuration.
type ParseError struct {
	Source string // The configuration source
	Line   int    // Line number where the error occurred (0 if unknown)
	Err    error  // The underlying error
}

// Error returns the error message.
func (e ParseError) Error() string {
	if e.Line > 0 {
		return fmt.Sprintf("config: parse error in %s at line %d: %v", e.Source, e.Line, e.Err)
	}
	return fmt.Sprintf("config: parse error in %s: %v", e.Source, e.Err)
}

// Unwrap returns the underlying error for use with errors.Is and errors.As.
func (e ParseError) Unwrap() error {
	return e.Err
}

// ValidationError represents a configuration validation error.
type ValidationError struct {
	Field   string // The field that failed validation
	Message string // Description of the validation failure
}

// Error returns the error message.
func (e ValidationError) Error() string {
	return fmt.Sprintf("config: validation error for %s: %s", e.Field, e.Message)
}
