package schema

import (
	"strings"
	"testing"
)

func TestValidateEmptyConfig(t *testing.T) {
	config := map[string]any{}
	result := Validate(config)

	if !result.Valid() {
		t.Errorf("empty config should be valid, got errors: %s", result.Error())
	}
}

func TestValidateLoggingLevel(t *testing.T) {
	tests := []struct {
		name      string
		level     string
		wantError bool
	}{
		{"debug is valid", "debug", false},
		{"info is valid", "info", false},
		{"warn is valid", "warn", false},
		{"error is valid", "error", false},
		{"trace is invalid", "trace", true},
		{"WARN uppercase is invalid", "WARN", true},
		{"empty is invalid", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := map[string]any{
				"logging": map[string]any{
					"level": tt.level,
				},
			}
			result := Validate(config)

			hasError := false
			for _, issue := range result.Issues() {
				if issue.Field == "logging.level" && issue.Severity == SeverityError {
					hasError = true
					break
				}
			}

			if hasError != tt.wantError {
				t.Errorf("level %q: wantError=%v, gotError=%v", tt.level, tt.wantError, hasError)
			}
		})
	}
}

func TestValidateLoggingFormat(t *testing.T) {
	tests := []struct {
		name      string
		format    string
		wantError bool
	}{
		{"text is valid", "text", false},
		{"json is valid", "json", false},
		{"xml is invalid", "xml", true},
		{"empty is invalid", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := map[string]any{
				"logging": map[string]any{
					"format": tt.format,
				},
			}
			result := Validate(config)

			hasError := false
			for _, issue := range result.Issues() {
				if issue.Field == "logging.format" && issue.Severity == SeverityError {
					hasError = true
					break
				}
			}

			if hasError != tt.wantError {
				t.Errorf("format %q: wantError=%v, gotError=%v", tt.format, tt.wantError, hasError)
			}
		})
	}
}

func TestValidateCodegenOutputFormat(t *testing.T) {
	tests := []struct {
		format    string
		wantError bool
	}{
		{"pretty", false},
		{"compact", false},
		{"minified", false},
		{"ugly", true},
	}

	for _, tt := range tests {
		t.Run(tt.format, func(t *testing.T) {
			config := map[string]any{
				"codegen": map[string]any{
					"output_format": tt.format,
				},
			}
			result := Validate(config)

			hasError := hasErrorForField(result, "codegen.output_format")
			if hasError != tt.wantError {
				t.Errorf("format %q: wantError=%v, gotError=%v", tt.format, tt.wantError, hasError)
			}
		})
	}
}

func TestValidateUITheme(t *testing.T) {
	tests := []struct {
		theme       string
		wantWarning bool
	}{
		{"default", false},
		{"light", false},
		{"dark", false},
		{"custom", true},
		{"solarized", true},
	}

	for _, tt := range tests {
		t.Run(tt.theme, func(t *testing.T) {
			config := map[string]any{
				"ui": map[string]any{
					"theme": tt.theme,
				},
			}
			result := Validate(config)

			hasWarning := hasWarningForField(result, "ui.theme")
			if hasWarning != tt.wantWarning {
				t.Errorf("theme %q: wantWarning=%v, gotWarning=%v", tt.theme, tt.wantWarning, hasWarning)
			}
		})
	}
}

func TestValidateCacheMaxSize(t *testing.T) {
	tests := []struct {
		name      string
		maxSize   any
		wantError bool
	}{
		{"positive int", 1024, false},
		{"zero", 0, false},
		{"negative", -1, true},
		{"large int64", int64(1024 * 1024 * 1024), false},
		{"negative int64", int64(-1), true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := map[string]any{
				"cache": map[string]any{
					"max_size": tt.maxSize,
				},
			}
			result := Validate(config)

			hasError := hasErrorForField(result, "cache.max_size")
			if hasError != tt.wantError {
				t.Errorf("max_size %v: wantError=%v, gotError=%v", tt.maxSize, tt.wantError, hasError)
			}
		})
	}
}

func TestValidatePath(t *testing.T) {
	tests := []struct {
		name      string
		path      string
		wantError bool
	}{
		{"normal path", "/var/log/morphir.log", false},
		{"relative path", "./output", false},
		{"empty path", "", false},
		{"path with null byte", "/var\x00/log", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := map[string]any{
				"logging": map[string]any{
					"file": tt.path,
				},
			}
			result := Validate(config)

			hasError := hasErrorForField(result, "logging.file")
			if hasError != tt.wantError {
				t.Errorf("path %q: wantError=%v, gotError=%v", tt.path, tt.wantError, hasError)
			}
		})
	}
}

func TestValidatePathLength(t *testing.T) {
	longPath := strings.Repeat("a", MaxPathLength+1)
	config := map[string]any{
		"workspace": map[string]any{
			"root": longPath,
		},
	}
	result := Validate(config)

	if !hasErrorForField(result, "workspace.root") {
		t.Error("expected error for path exceeding max length")
	}
}

func TestValidateIRFormatVersion(t *testing.T) {
	tests := []struct {
		version     int
		wantWarning bool
	}{
		{1, false},
		{3, false},
		{10, false},
		{0, true},
		{11, true},
		{-1, true},
	}

	for _, tt := range tests {
		t.Run("version "+string(rune('0'+tt.version)), func(t *testing.T) {
			config := map[string]any{
				"ir": map[string]any{
					"format_version": tt.version,
				},
			}
			result := Validate(config)

			hasWarning := hasWarningForField(result, "ir.format_version")
			if hasWarning != tt.wantWarning {
				t.Errorf("version %d: wantWarning=%v, gotWarning=%v", tt.version, tt.wantWarning, hasWarning)
			}
		})
	}
}

func TestValidateCodegenTargets(t *testing.T) {
	t.Run("valid targets", func(t *testing.T) {
		config := map[string]any{
			"codegen": map[string]any{
				"targets": []string{"go", "typescript", "scala"},
			},
		}
		result := Validate(config)
		if result.HasErrors() {
			t.Errorf("valid targets should not have errors: %s", result.Error())
		}
	})

	t.Run("empty string target", func(t *testing.T) {
		config := map[string]any{
			"codegen": map[string]any{
				"targets": []string{"go", "", "scala"},
			},
		}
		result := Validate(config)
		if !result.HasWarnings() {
			t.Error("empty target should produce warning")
		}
	})

	t.Run("targets as []any", func(t *testing.T) {
		config := map[string]any{
			"codegen": map[string]any{
				"targets": []any{"go", "typescript"},
			},
		}
		result := Validate(config)
		if result.HasErrors() {
			t.Errorf("[]any targets should be valid: %s", result.Error())
		}
	})

	t.Run("invalid target type", func(t *testing.T) {
		config := map[string]any{
			"codegen": map[string]any{
				"targets": []any{"go", 123},
			},
		}
		result := Validate(config)
		if !result.HasErrors() {
			t.Error("non-string target should produce error")
		}
	})

	t.Run("invalid targets type", func(t *testing.T) {
		config := map[string]any{
			"codegen": map[string]any{
				"targets": "go",
			},
		}
		result := Validate(config)
		if !result.HasErrors() {
			t.Error("string targets should produce error")
		}
	})
}

func TestValidateMorphirVersion(t *testing.T) {
	tests := []struct {
		version     string
		wantWarning bool
	}{
		{"1.0.0", false},
		{"^1.2.3", false},
		{">=1.0.0, <2.0.0", false},
		{"1.0.0-beta.1", false},
		{"", false},
		{"not@valid!", true},
	}

	for _, tt := range tests {
		t.Run(tt.version, func(t *testing.T) {
			config := map[string]any{
				"morphir": map[string]any{
					"version": tt.version,
				},
			}
			result := Validate(config)

			hasWarning := hasWarningForField(result, "morphir.version")
			if hasWarning != tt.wantWarning {
				t.Errorf("version %q: wantWarning=%v, gotWarning=%v", tt.version, tt.wantWarning, hasWarning)
			}
		})
	}
}

func TestValidateMultipleErrors(t *testing.T) {
	config := map[string]any{
		"logging": map[string]any{
			"level":  "trace",
			"format": "xml",
		},
		"cache": map[string]any{
			"max_size": -100,
		},
	}
	result := Validate(config)

	errors := result.Errors()
	if len(errors) != 3 {
		t.Errorf("expected 3 errors, got %d: %v", len(errors), errors)
	}
}

func TestValidateMissingSections(t *testing.T) {
	// Config with no sections should be valid
	config := map[string]any{}
	result := Validate(config)

	if !result.Valid() {
		t.Errorf("config with no sections should be valid: %s", result.Error())
	}
}

func TestValidateWrongSectionType(t *testing.T) {
	// Section that's not a map should be silently ignored
	config := map[string]any{
		"logging": "not a map",
	}
	result := Validate(config)

	if !result.Valid() {
		t.Errorf("wrong section type should be ignored: %s", result.Error())
	}
}

func TestValidateWorkflows(t *testing.T) {
	t.Run("valid workflow", func(t *testing.T) {
		config := map[string]any{
			"workflows": map[string]any{
				"build": map[string]any{
					"description": "Build workflow",
					"stages": []any{
						map[string]any{
							"name":    "compile",
							"targets": []string{"make"},
						},
						map[string]any{
							"name":     "generate",
							"targets":  []any{"gen:scala"},
							"parallel": true,
						},
					},
				},
			},
		}
		result := Validate(config)
		if result.HasErrors() {
			t.Fatalf("valid workflows should not have errors: %s", result.Error())
		}
	})

	t.Run("invalid workflow section type", func(t *testing.T) {
		config := map[string]any{
			"workflows": "not a table",
		}
		result := Validate(config)
		if !hasErrorForField(result, "workflows") {
			t.Error("expected error for invalid workflows section")
		}
	})

	t.Run("invalid stage targets", func(t *testing.T) {
		config := map[string]any{
			"workflows": map[string]any{
				"ci": map[string]any{
					"stages": []any{
						map[string]any{
							"name":    "compile",
							"targets": "make",
						},
					},
				},
			},
		}
		result := Validate(config)
		if !hasErrorForField(result, "workflows.ci.stages[0].targets") {
			t.Error("expected error for invalid stage targets")
		}
	})
}

// Helper functions

func hasErrorForField(result *Result, field string) bool {
	for _, issue := range result.Issues() {
		if issue.Field == field && issue.Severity == SeverityError {
			return true
		}
	}
	return false
}

func hasWarningForField(result *Result, field string) bool {
	for _, issue := range result.Issues() {
		if issue.Field == field && issue.Severity == SeverityWarning {
			return true
		}
	}
	return false
}
