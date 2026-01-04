// Package schema provides configuration schema validation.
package schema

import (
	"fmt"
	"strings"
)

// Severity indicates the severity of a validation issue.
type Severity int

const (
	// SeverityWarning indicates a non-fatal issue that should be addressed.
	SeverityWarning Severity = iota
	// SeverityError indicates a fatal issue that prevents valid configuration.
	SeverityError
)

// String returns the string representation of the severity.
func (s Severity) String() string {
	switch s {
	case SeverityWarning:
		return "warning"
	case SeverityError:
		return "error"
	default:
		return "unknown"
	}
}

// Issue represents a single validation issue.
type Issue struct {
	Field    string   // The field path (e.g., "logging.level")
	Message  string   // Human-readable error message
	Severity Severity // Warning or error
	Value    any      // The invalid value (optional)
}

// Error returns the error message for the issue.
func (i Issue) Error() string {
	return fmt.Sprintf("%s: %s", i.Field, i.Message)
}

// Result contains all validation issues found during validation.
type Result struct {
	issues []Issue
}

// NewResult creates an empty validation result.
func NewResult() *Result {
	return &Result{
		issues: make([]Issue, 0),
	}
}

// AddError adds an error-level issue.
func (r *Result) AddError(field, message string, value any) {
	r.issues = append(r.issues, Issue{
		Field:    field,
		Message:  message,
		Severity: SeverityError,
		Value:    value,
	})
}

// AddWarning adds a warning-level issue.
func (r *Result) AddWarning(field, message string, value any) {
	r.issues = append(r.issues, Issue{
		Field:    field,
		Message:  message,
		Severity: SeverityWarning,
		Value:    value,
	})
}

// Issues returns all validation issues.
func (r *Result) Issues() []Issue {
	if len(r.issues) == 0 {
		return nil
	}
	result := make([]Issue, len(r.issues))
	copy(result, r.issues)
	return result
}

// Errors returns only error-level issues.
func (r *Result) Errors() []Issue {
	var errors []Issue
	for _, issue := range r.issues {
		if issue.Severity == SeverityError {
			errors = append(errors, issue)
		}
	}
	return errors
}

// Warnings returns only warning-level issues.
func (r *Result) Warnings() []Issue {
	var warnings []Issue
	for _, issue := range r.issues {
		if issue.Severity == SeverityWarning {
			warnings = append(warnings, issue)
		}
	}
	return warnings
}

// HasErrors returns true if there are any error-level issues.
func (r *Result) HasErrors() bool {
	for _, issue := range r.issues {
		if issue.Severity == SeverityError {
			return true
		}
	}
	return false
}

// HasWarnings returns true if there are any warning-level issues.
func (r *Result) HasWarnings() bool {
	for _, issue := range r.issues {
		if issue.Severity == SeverityWarning {
			return true
		}
	}
	return false
}

// Valid returns true if there are no error-level issues.
func (r *Result) Valid() bool {
	return !r.HasErrors()
}

// Error returns a combined error message for all errors.
// Returns empty string if there are no errors.
func (r *Result) Error() string {
	errors := r.Errors()
	if len(errors) == 0 {
		return ""
	}

	var msgs []string
	for _, err := range errors {
		msgs = append(msgs, err.Error())
	}
	return strings.Join(msgs, "; ")
}

// String returns a human-readable summary of all issues.
func (r *Result) String() string {
	if len(r.issues) == 0 {
		return "configuration is valid"
	}

	var b strings.Builder
	errors := r.Errors()
	warnings := r.Warnings()

	if len(errors) > 0 {
		b.WriteString(fmt.Sprintf("%d error(s):\n", len(errors)))
		for _, err := range errors {
			b.WriteString(fmt.Sprintf("  - %s\n", err.Error()))
		}
	}

	if len(warnings) > 0 {
		if len(errors) > 0 {
			b.WriteString("\n")
		}
		b.WriteString(fmt.Sprintf("%d warning(s):\n", len(warnings)))
		for _, warn := range warnings {
			b.WriteString(fmt.Sprintf("  - %s\n", warn.Error()))
		}
	}

	return b.String()
}

// Merge combines another result into this one.
func (r *Result) Merge(other *Result) {
	if other == nil {
		return
	}
	r.issues = append(r.issues, other.issues...)
}
