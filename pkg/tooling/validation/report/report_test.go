package report

import (
	"strings"
	"testing"

	"github.com/finos/morphir/pkg/tooling/validation"
)

func TestAssignErrorCode(t *testing.T) {
	tests := []struct {
		name     string
		message  string
		expected ErrorCode
	}{
		{
			name:     "pattern mismatch",
			message:  "'2052' does not match pattern '^[a-z][a-z0-9]*$'",
			expected: E001,
		},
		{
			name:     "oneOf failed",
			message:  "oneOf failed, got null",
			expected: E002,
		},
		{
			name:     "allOf failed",
			message:  "allOf failed, got string",
			expected: E003,
		},
		{
			name:     "missing properties",
			message:  "missing properties: 'name', 'value'",
			expected: E004,
		},
		{
			name:     "minItems constraint",
			message:  "minItems must be 2, got 1",
			expected: E005,
		},
		{
			name:     "maxItems constraint",
			message:  "maxItems must be 5, got 10",
			expected: E005,
		},
		{
			name:     "got array want object",
			message:  "got array, want object",
			expected: E006,
		},
		{
			name:     "got object want array",
			message:  "got object, want array",
			expected: E006,
		},
		{
			name:     "got null",
			message:  "got null, want string",
			expected: E007,
		},
		{
			name:     "unknown error",
			message:  "some unknown validation error",
			expected: E000,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed := ParsedError{Message: tt.message}
			code := assignErrorCode(parsed)
			if code != tt.expected {
				t.Errorf("assignErrorCode() = %v, want %v", code, tt.expected)
			}
		})
	}
}

func TestGetErrorCodeInfo(t *testing.T) {
	tests := []struct {
		code          ErrorCode
		expectedTitle string
	}{
		{E001, "Pattern Mismatch"},
		{E002, "Type Variant Mismatch"},
		{E003, "Constraint Validation Failed"},
		{E004, "Missing Required Fields"},
		{E005, "Array Length Mismatch"},
		{E006, "Type Mismatch"},
		{E007, "Null Value"},
		{E000, "Other Validation Error"},
	}

	for _, tt := range tests {
		t.Run(string(tt.code), func(t *testing.T) {
			info := GetErrorCodeInfo(tt.code)
			if info.Title != tt.expectedTitle {
				t.Errorf("GetErrorCodeInfo(%v).Title = %v, want %v", tt.code, info.Title, tt.expectedTitle)
			}
			if info.Description == "" {
				t.Errorf("GetErrorCodeInfo(%v).Description should not be empty", tt.code)
			}
		})
	}

	// Test unknown code returns E000 info
	t.Run("unknown code", func(t *testing.T) {
		info := GetErrorCodeInfo(ErrorCode("E999"))
		if info.Title != "Other Validation Error" {
			t.Errorf("GetErrorCodeInfo(E999).Title = %v, want 'Other Validation Error'", info.Title)
		}
	})
}

func TestParseValidationErrorAssignsCode(t *testing.T) {
	errStr := "at '/distribution/3/modules/0/0/1/2': '2052' does not match pattern '^[a-z][a-z0-9]*$'"

	errors := parseValidationError(errStr)

	if len(errors) != 1 {
		t.Fatalf("Expected 1 error, got %d", len(errors))
	}

	if errors[0].Code != E001 {
		t.Errorf("Expected error code E001, got %v", errors[0].Code)
	}
}

func TestMarkdownGeneratorIncludesAppendix(t *testing.T) {
	result := &validation.Result{
		Valid:   false,
		Version: 3,
		Path:    "test.ir.json",
		Errors: []string{
			"at '/distribution/0': '2052' does not match pattern '^[a-z][a-z0-9]*$'",
			"at '/distribution/1': oneOf failed, got null",
		},
	}

	generator := &MarkdownGenerator{}
	report := generator.Generate(result)

	// Verify appendix section exists
	if !strings.Contains(report, "## Appendix: Error Code Reference") {
		t.Error("Report should contain appendix section")
	}

	// Verify error codes are referenced in appendix
	if !strings.Contains(report, "### E001: Pattern Mismatch") {
		t.Error("Report appendix should contain E001 definition")
	}

	if !strings.Contains(report, "### E002: Type Variant Mismatch") {
		t.Error("Report appendix should contain E002 definition")
	}

	// Verify unused codes are not included
	if strings.Contains(report, "### E004: Missing Required Fields") {
		t.Error("Report appendix should not contain unused E004 definition")
	}
}

func TestMarkdownGeneratorInlineErrorCodes(t *testing.T) {
	result := &validation.Result{
		Valid:   false,
		Version: 3,
		Path:    "test.ir.json",
		Errors: []string{
			"at '/distribution/0': '2052' does not match pattern '^[a-z][a-z0-9]*$'",
		},
	}

	generator := &MarkdownGenerator{}
	report := generator.Generate(result)

	// Verify error code appears inline in issue description
	if !strings.Contains(report, "**Issue:** [E001]") {
		t.Error("Report should include error code inline in issue description")
	}
}

func TestMarkdownGeneratorNoAppendixForValidResult(t *testing.T) {
	result := &validation.Result{
		Valid:   true,
		Version: 3,
		Path:    "test.ir.json",
		Errors:  []string{},
	}

	generator := &MarkdownGenerator{}
	report := generator.Generate(result)

	// Verify no appendix section for valid result
	if strings.Contains(report, "## Appendix: Error Code Reference") {
		t.Error("Report for valid result should not contain appendix section")
	}
}

func TestAppendixOrderedCodes(t *testing.T) {
	result := &validation.Result{
		Valid:   false,
		Version: 3,
		Path:    "test.ir.json",
		Errors: []string{
			"at '/a': got null, want string",                   // E007
			"at '/b': '123' does not match pattern '^[a-z]+$'", // E001
			"at '/c': oneOf failed",                            // E002
		},
	}

	generator := &MarkdownGenerator{}
	report := generator.Generate(result)

	// Find positions of each error code in appendix
	e001Pos := strings.Index(report, "### E001: Pattern Mismatch")
	e002Pos := strings.Index(report, "### E002: Type Variant Mismatch")
	e007Pos := strings.Index(report, "### E007: Null Value")

	if e001Pos == -1 || e002Pos == -1 || e007Pos == -1 {
		t.Fatal("Expected all three error codes in appendix")
	}

	// Verify they appear in order E001 < E002 < E007
	if e001Pos >= e002Pos || e002Pos >= e007Pos {
		t.Errorf("Error codes should be ordered: E001(%d) < E002(%d) < E007(%d)", e001Pos, e002Pos, e007Pos)
	}
}
