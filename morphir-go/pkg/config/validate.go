package config

import (
	"github.com/finos/morphir-go/pkg/config/internal/schema"
)

// ValidationSeverity indicates the severity of a validation issue.
type ValidationSeverity int

const (
	// SeverityWarning indicates a non-fatal issue.
	SeverityWarning ValidationSeverity = ValidationSeverity(schema.SeverityWarning)
	// SeverityError indicates a fatal issue.
	SeverityError ValidationSeverity = ValidationSeverity(schema.SeverityError)
)

// String returns the string representation of the severity.
func (s ValidationSeverity) String() string {
	return schema.Severity(s).String()
}

// ValidationIssue represents a single validation issue.
type ValidationIssue struct {
	field    string
	message  string
	severity ValidationSeverity
	value    any
}

// Field returns the field path (e.g., "logging.level").
func (i ValidationIssue) Field() string {
	return i.field
}

// Message returns the human-readable error message.
func (i ValidationIssue) Message() string {
	return i.message
}

// Severity returns the issue severity.
func (i ValidationIssue) Severity() ValidationSeverity {
	return i.severity
}

// Value returns the invalid value that caused the issue.
func (i ValidationIssue) Value() any {
	return i.value
}

// Error returns the error message for the issue.
func (i ValidationIssue) Error() string {
	return i.field + ": " + i.message
}

// ValidationResult contains all validation issues found.
type ValidationResult struct {
	result *schema.Result
}

// Issues returns all validation issues.
func (r ValidationResult) Issues() []ValidationIssue {
	schemaIssues := r.result.Issues()
	if len(schemaIssues) == 0 {
		return nil
	}
	issues := make([]ValidationIssue, len(schemaIssues))
	for i, si := range schemaIssues {
		issues[i] = ValidationIssue{
			field:    si.Field,
			message:  si.Message,
			severity: ValidationSeverity(si.Severity),
			value:    si.Value,
		}
	}
	return issues
}

// Errors returns only error-level issues.
func (r ValidationResult) Errors() []ValidationIssue {
	schemaErrors := r.result.Errors()
	if len(schemaErrors) == 0 {
		return nil
	}
	errors := make([]ValidationIssue, len(schemaErrors))
	for i, se := range schemaErrors {
		errors[i] = ValidationIssue{
			field:    se.Field,
			message:  se.Message,
			severity: SeverityError,
			value:    se.Value,
		}
	}
	return errors
}

// Warnings returns only warning-level issues.
func (r ValidationResult) Warnings() []ValidationIssue {
	schemaWarnings := r.result.Warnings()
	if len(schemaWarnings) == 0 {
		return nil
	}
	warnings := make([]ValidationIssue, len(schemaWarnings))
	for i, sw := range schemaWarnings {
		warnings[i] = ValidationIssue{
			field:    sw.Field,
			message:  sw.Message,
			severity: SeverityWarning,
			value:    sw.Value,
		}
	}
	return warnings
}

// Valid returns true if there are no error-level issues.
func (r ValidationResult) Valid() bool {
	return r.result.Valid()
}

// HasErrors returns true if there are any error-level issues.
func (r ValidationResult) HasErrors() bool {
	return r.result.HasErrors()
}

// HasWarnings returns true if there are any warning-level issues.
func (r ValidationResult) HasWarnings() bool {
	return r.result.HasWarnings()
}

// Error returns a combined error message for all errors.
func (r ValidationResult) Error() string {
	return r.result.Error()
}

// String returns a human-readable summary of all issues.
func (r ValidationResult) String() string {
	return r.result.String()
}

// ValidateMap validates a configuration map and returns all issues found.
// This is useful for validating raw configuration before converting to Config.
func ValidateMap(config map[string]any) ValidationResult {
	return ValidationResult{result: schema.Validate(config)}
}
