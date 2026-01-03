package schema

import (
	"strings"
	"testing"
)

func TestSeverityString(t *testing.T) {
	tests := []struct {
		severity Severity
		want     string
	}{
		{SeverityWarning, "warning"},
		{SeverityError, "error"},
		{Severity(99), "unknown"},
	}

	for _, tt := range tests {
		if got := tt.severity.String(); got != tt.want {
			t.Errorf("Severity(%d).String() = %q, want %q", tt.severity, got, tt.want)
		}
	}
}

func TestIssueError(t *testing.T) {
	issue := Issue{
		Field:   "logging.level",
		Message: "invalid value",
	}

	want := "logging.level: invalid value"
	if got := issue.Error(); got != want {
		t.Errorf("Issue.Error() = %q, want %q", got, want)
	}
}

func TestResultAddError(t *testing.T) {
	result := NewResult()
	result.AddError("logging.level", "invalid value", "trace")

	if !result.HasErrors() {
		t.Error("expected HasErrors() to be true")
	}
	if result.Valid() {
		t.Error("expected Valid() to be false")
	}

	errors := result.Errors()
	if len(errors) != 1 {
		t.Fatalf("expected 1 error, got %d", len(errors))
	}
	if errors[0].Field != "logging.level" {
		t.Errorf("Field = %q, want %q", errors[0].Field, "logging.level")
	}
	if errors[0].Severity != SeverityError {
		t.Errorf("Severity = %v, want %v", errors[0].Severity, SeverityError)
	}
}

func TestResultAddWarning(t *testing.T) {
	result := NewResult()
	result.AddWarning("ui.theme", "unknown theme", "custom")

	if !result.HasWarnings() {
		t.Error("expected HasWarnings() to be true")
	}
	if result.HasErrors() {
		t.Error("expected HasErrors() to be false")
	}
	if !result.Valid() {
		t.Error("expected Valid() to be true (warnings don't invalidate)")
	}

	warnings := result.Warnings()
	if len(warnings) != 1 {
		t.Fatalf("expected 1 warning, got %d", len(warnings))
	}
	if warnings[0].Severity != SeverityWarning {
		t.Errorf("Severity = %v, want %v", warnings[0].Severity, SeverityWarning)
	}
}

func TestResultIssuesDefensiveCopy(t *testing.T) {
	result := NewResult()
	result.AddError("field", "message", nil)

	issues1 := result.Issues()
	issues2 := result.Issues()

	if len(issues1) > 0 {
		issues1[0].Field = "modified"
	}

	if len(issues2) > 0 && issues2[0].Field == "modified" {
		t.Error("Issues() should return a defensive copy")
	}
}

func TestResultError(t *testing.T) {
	t.Run("no errors", func(t *testing.T) {
		result := NewResult()
		result.AddWarning("field", "warning", nil)

		if got := result.Error(); got != "" {
			t.Errorf("Error() = %q, want empty string", got)
		}
	})

	t.Run("single error", func(t *testing.T) {
		result := NewResult()
		result.AddError("logging.level", "invalid", nil)

		want := "logging.level: invalid"
		if got := result.Error(); got != want {
			t.Errorf("Error() = %q, want %q", got, want)
		}
	})

	t.Run("multiple errors", func(t *testing.T) {
		result := NewResult()
		result.AddError("logging.level", "invalid level", nil)
		result.AddError("logging.format", "invalid format", nil)

		got := result.Error()
		if !strings.Contains(got, "logging.level") {
			t.Errorf("Error() should contain 'logging.level', got %q", got)
		}
		if !strings.Contains(got, "logging.format") {
			t.Errorf("Error() should contain 'logging.format', got %q", got)
		}
	})
}

func TestResultString(t *testing.T) {
	t.Run("empty result", func(t *testing.T) {
		result := NewResult()
		got := result.String()
		if got != "configuration is valid" {
			t.Errorf("String() = %q, want %q", got, "configuration is valid")
		}
	})

	t.Run("with errors and warnings", func(t *testing.T) {
		result := NewResult()
		result.AddError("logging.level", "invalid", nil)
		result.AddWarning("ui.theme", "unknown", nil)

		got := result.String()
		if !strings.Contains(got, "1 error(s)") {
			t.Errorf("String() should contain '1 error(s)', got %q", got)
		}
		if !strings.Contains(got, "1 warning(s)") {
			t.Errorf("String() should contain '1 warning(s)', got %q", got)
		}
	})
}

func TestResultMerge(t *testing.T) {
	result1 := NewResult()
	result1.AddError("field1", "error1", nil)

	result2 := NewResult()
	result2.AddWarning("field2", "warning2", nil)

	result1.Merge(result2)

	if len(result1.Issues()) != 2 {
		t.Errorf("expected 2 issues after merge, got %d", len(result1.Issues()))
	}
	if len(result1.Errors()) != 1 {
		t.Errorf("expected 1 error, got %d", len(result1.Errors()))
	}
	if len(result1.Warnings()) != 1 {
		t.Errorf("expected 1 warning, got %d", len(result1.Warnings()))
	}
}

func TestResultMergeNil(t *testing.T) {
	result := NewResult()
	result.AddError("field", "message", nil)

	result.Merge(nil) // Should not panic

	if len(result.Issues()) != 1 {
		t.Errorf("expected 1 issue, got %d", len(result.Issues()))
	}
}

func TestEmptyResultValid(t *testing.T) {
	result := NewResult()
	if !result.Valid() {
		t.Error("empty result should be valid")
	}
	if result.HasErrors() {
		t.Error("empty result should have no errors")
	}
	if result.HasWarnings() {
		t.Error("empty result should have no warnings")
	}
}
