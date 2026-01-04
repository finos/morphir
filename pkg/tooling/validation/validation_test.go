package validation

import (
	"os"
	"path/filepath"
	"testing"
)

func TestValidateBytes_ValidV3(t *testing.T) {
	// Minimal valid v3 IR
	// Structure: ["Library", PackageName, Dependencies, PackageDefinition]
	// PackageName is a Path = array of Names, each Name is array of lowercase strings
	validIR := []byte(`{
		"formatVersion": 3,
		"distribution": ["Library", [["test"]], [], {"modules": []}]
	}`)

	result, err := ValidateBytes(validIR, "test.json", DefaultOptions())
	if err != nil {
		t.Fatalf("ValidateBytes() error = %v", err)
	}
	if !result.Valid {
		t.Errorf("ValidateBytes() expected valid, got errors: %v", result.Errors)
	}
	if result.Version != 3 {
		t.Errorf("ValidateBytes() version = %d, want 3", result.Version)
	}
}

func TestValidateBytes_InvalidJSON(t *testing.T) {
	invalidJSON := []byte(`{not valid json}`)

	result, err := ValidateBytes(invalidJSON, "test.json", DefaultOptions())
	if err != nil {
		t.Fatalf("ValidateBytes() error = %v", err)
	}
	if result.Valid {
		t.Error("ValidateBytes() expected invalid for malformed JSON")
	}
	if len(result.Errors) == 0 {
		t.Error("ValidateBytes() expected errors for malformed JSON")
	}
}

func TestValidateBytes_InvalidVersion(t *testing.T) {
	invalidVersion := []byte(`{"formatVersion": 99}`)

	result, err := ValidateBytes(invalidVersion, "test.json", DefaultOptions())
	if err != nil {
		t.Fatalf("ValidateBytes() error = %v", err)
	}
	if result.Valid {
		t.Error("ValidateBytes() expected invalid for unsupported version")
	}
}

func TestValidateBytes_MissingDistribution(t *testing.T) {
	// Valid JSON but missing required distribution field
	missingField := []byte(`{"formatVersion": 3}`)

	result, err := ValidateBytes(missingField, "test.json", DefaultOptions())
	if err != nil {
		t.Fatalf("ValidateBytes() error = %v", err)
	}
	if result.Valid {
		t.Error("ValidateBytes() expected invalid for missing distribution")
	}
}

func TestDetectVersion(t *testing.T) {
	tests := []struct {
		name    string
		data    []byte
		want    int
		wantErr bool
	}{
		{
			name: "v1",
			data: []byte(`{"formatVersion": 1}`),
			want: 1,
		},
		{
			name: "v2",
			data: []byte(`{"formatVersion": 2}`),
			want: 2,
		},
		{
			name: "v3",
			data: []byte(`{"formatVersion": 3}`),
			want: 3,
		},
		{
			name:    "invalid version 0",
			data:    []byte(`{"formatVersion": 0}`),
			wantErr: true,
		},
		{
			name:    "invalid version 99",
			data:    []byte(`{"formatVersion": 99}`),
			wantErr: true,
		},
		{
			name:    "invalid JSON",
			data:    []byte(`not json`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := detectVersion(tt.data)
			if (err != nil) != tt.wantErr {
				t.Errorf("detectVersion() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && got != tt.want {
				t.Errorf("detectVersion() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestFindIRFile(t *testing.T) {
	// Create temp directory with morphir.ir.json
	tmpDir := t.TempDir()
	irPath := filepath.Join(tmpDir, "morphir.ir.json")
	if err := os.WriteFile(irPath, []byte(`{}`), 0644); err != nil {
		t.Fatalf("failed to create test file: %v", err)
	}

	t.Run("find in directory", func(t *testing.T) {
		found, err := FindIRFile(tmpDir)
		if err != nil {
			t.Fatalf("FindIRFile() error = %v", err)
		}
		if found != irPath {
			t.Errorf("FindIRFile() = %v, want %v", found, irPath)
		}
	})

	t.Run("direct file path", func(t *testing.T) {
		found, err := FindIRFile(irPath)
		if err != nil {
			t.Fatalf("FindIRFile() error = %v", err)
		}
		if found != irPath {
			t.Errorf("FindIRFile() = %v, want %v", found, irPath)
		}
	})

	t.Run("not found", func(t *testing.T) {
		emptyDir := t.TempDir()
		_, err := FindIRFile(emptyDir)
		if err == nil {
			t.Error("FindIRFile() expected error for missing file")
		}
	})
}
