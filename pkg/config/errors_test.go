package config

import (
	"errors"
	"fmt"
	"testing"
)

func TestLoadErrorWithSource(t *testing.T) {
	underlying := errors.New("file not found")
	err := LoadError{
		Source: "/path/to/config.toml",
		Err:    underlying,
	}

	want := "config: load error from /path/to/config.toml: file not found"
	if got := err.Error(); got != want {
		t.Errorf("Error: want %q, got %q", want, got)
	}
}

func TestLoadErrorWithoutSource(t *testing.T) {
	underlying := errors.New("unknown error")
	err := LoadError{
		Source: "",
		Err:    underlying,
	}

	want := "config: load error: unknown error"
	if got := err.Error(); got != want {
		t.Errorf("Error: want %q, got %q", want, got)
	}
}

func TestLoadErrorUnwrap(t *testing.T) {
	underlying := ErrNotFound
	err := LoadError{
		Source: "/path/to/config.toml",
		Err:    underlying,
	}

	if !errors.Is(err, ErrNotFound) {
		t.Error("expected errors.Is(err, ErrNotFound) to be true")
	}
}

func TestParseErrorWithLine(t *testing.T) {
	underlying := errors.New("invalid syntax")
	err := ParseError{
		Source: "morphir.toml",
		Line:   42,
		Err:    underlying,
	}

	want := "config: parse error in morphir.toml at line 42: invalid syntax"
	if got := err.Error(); got != want {
		t.Errorf("Error: want %q, got %q", want, got)
	}
}

func TestParseErrorWithoutLine(t *testing.T) {
	underlying := errors.New("invalid syntax")
	err := ParseError{
		Source: "morphir.toml",
		Line:   0,
		Err:    underlying,
	}

	want := "config: parse error in morphir.toml: invalid syntax"
	if got := err.Error(); got != want {
		t.Errorf("Error: want %q, got %q", want, got)
	}
}

func TestParseErrorUnwrap(t *testing.T) {
	underlying := ErrInvalidFormat
	err := ParseError{
		Source: "morphir.toml",
		Err:    underlying,
	}

	if !errors.Is(err, ErrInvalidFormat) {
		t.Error("expected errors.Is(err, ErrInvalidFormat) to be true")
	}
}

func TestValidationError(t *testing.T) {
	err := ValidationError{
		Field:   "ir.format_version",
		Message: "must be a positive integer",
	}

	want := "config: validation error for ir.format_version: must be a positive integer"
	if got := err.Error(); got != want {
		t.Errorf("Error: want %q, got %q", want, got)
	}
}

func TestSentinelErrors(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want string
	}{
		{"ErrNotFound", ErrNotFound, "config: not found"},
		{"ErrInvalidFormat", ErrInvalidFormat, "config: invalid format"},
		{"ErrMergeConflict", ErrMergeConflict, "config: merge conflict"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.err.Error(); got != tt.want {
				t.Errorf("Error: want %q, got %q", tt.want, got)
			}
		})
	}
}

func TestErrorWrapping(t *testing.T) {
	// Test that wrapped errors can be detected
	loadErr := LoadError{
		Source: "test.toml",
		Err:    fmt.Errorf("wrapped: %w", ErrNotFound),
	}

	if !errors.Is(loadErr, ErrNotFound) {
		t.Error("expected nested ErrNotFound to be detectable via errors.Is")
	}
}
