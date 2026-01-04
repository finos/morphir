package config

import (
	"testing"
)

func TestValidationSeverityString(t *testing.T) {
	if SeverityWarning.String() != "warning" {
		t.Errorf("SeverityWarning.String() = %q, want %q", SeverityWarning.String(), "warning")
	}
	if SeverityError.String() != "error" {
		t.Errorf("SeverityError.String() = %q, want %q", SeverityError.String(), "error")
	}
}

func TestValidationIssueError(t *testing.T) {
	issue := ValidationIssue{
		field:   "logging.level",
		message: "invalid value",
	}

	want := "logging.level: invalid value"
	if got := issue.Error(); got != want {
		t.Errorf("Error() = %q, want %q", got, want)
	}
}

func TestValidationIssueGetters(t *testing.T) {
	issue := ValidationIssue{
		field:    "logging.level",
		message:  "invalid value",
		severity: SeverityError,
		value:    "trace",
	}

	if issue.Field() != "logging.level" {
		t.Errorf("Field() = %q, want %q", issue.Field(), "logging.level")
	}
	if issue.Message() != "invalid value" {
		t.Errorf("Message() = %q, want %q", issue.Message(), "invalid value")
	}
	if issue.Severity() != SeverityError {
		t.Errorf("Severity() = %v, want %v", issue.Severity(), SeverityError)
	}
	if issue.Value() != "trace" {
		t.Errorf("Value() = %v, want %v", issue.Value(), "trace")
	}
}

func TestValidateMapValid(t *testing.T) {
	config := map[string]any{
		"logging": map[string]any{
			"level":  "info",
			"format": "json",
		},
		"ui": map[string]any{
			"theme": "dark",
		},
	}

	result := ValidateMap(config)

	if !result.Valid() {
		t.Errorf("valid config should be valid, got errors: %s", result.Error())
	}
	if result.HasErrors() {
		t.Error("valid config should have no errors")
	}
}

func TestValidateMapInvalid(t *testing.T) {
	config := map[string]any{
		"logging": map[string]any{
			"level":  "trace",
			"format": "xml",
		},
	}

	result := ValidateMap(config)

	if result.Valid() {
		t.Error("invalid config should not be valid")
	}
	if !result.HasErrors() {
		t.Error("invalid config should have errors")
	}

	errors := result.Errors()
	if len(errors) != 2 {
		t.Errorf("expected 2 errors, got %d", len(errors))
	}
}

func TestValidateMapWithWarnings(t *testing.T) {
	config := map[string]any{
		"ui": map[string]any{
			"theme": "custom-theme",
		},
	}

	result := ValidateMap(config)

	if !result.Valid() {
		t.Error("config with only warnings should be valid")
	}
	if !result.HasWarnings() {
		t.Error("expected warnings for unknown theme")
	}
	if result.HasErrors() {
		t.Error("should not have errors")
	}

	warnings := result.Warnings()
	if len(warnings) != 1 {
		t.Errorf("expected 1 warning, got %d", len(warnings))
	}
}

func TestValidateMapEmpty(t *testing.T) {
	config := map[string]any{}
	result := ValidateMap(config)

	if !result.Valid() {
		t.Error("empty config should be valid")
	}
}

func TestValidationResultIssues(t *testing.T) {
	config := map[string]any{
		"logging": map[string]any{
			"level": "trace",
		},
		"ui": map[string]any{
			"theme": "custom",
		},
	}

	result := ValidateMap(config)
	issues := result.Issues()

	if len(issues) != 2 {
		t.Errorf("expected 2 issues, got %d", len(issues))
	}
}

func TestValidationResultString(t *testing.T) {
	t.Run("valid", func(t *testing.T) {
		result := ValidateMap(map[string]any{})
		got := result.String()
		if got != "configuration is valid" {
			t.Errorf("String() = %q, want 'configuration is valid'", got)
		}
	})

	t.Run("with errors", func(t *testing.T) {
		config := map[string]any{
			"logging": map[string]any{
				"level": "trace",
			},
		}
		result := ValidateMap(config)
		got := result.String()
		if got == "" {
			t.Error("String() should not be empty for invalid config")
		}
	})
}

func TestValidationResultError(t *testing.T) {
	t.Run("no errors", func(t *testing.T) {
		result := ValidateMap(map[string]any{})
		if result.Error() != "" {
			t.Error("Error() should be empty for valid config")
		}
	})

	t.Run("with errors", func(t *testing.T) {
		config := map[string]any{
			"logging": map[string]any{
				"level": "trace",
			},
		}
		result := ValidateMap(config)
		if result.Error() == "" {
			t.Error("Error() should not be empty for invalid config")
		}
	})
}
