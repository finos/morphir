package sources

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDotEnvSourceName(t *testing.T) {
	src := NewDotEnvSource("user", "/path/to/.env", "MORPHIR", 5)

	if got := src.Name(); got != "user" {
		t.Errorf("Name: want user, got %q", got)
	}
}

func TestDotEnvSourcePriority(t *testing.T) {
	src := NewDotEnvSource("user", "/path/to/.env", "MORPHIR", 5)

	if got := src.Priority(); got != 5 {
		t.Errorf("Priority: want 5, got %d", got)
	}
}

func TestDotEnvSourcePath(t *testing.T) {
	src := NewDotEnvSource("user", "/path/to/.env", "MORPHIR", 5)

	if got := src.Path(); got != "/path/to/.env" {
		t.Errorf("Path: want /path/to/.env, got %q", got)
	}
}

func TestDotEnvSourceExistsForExistingFile(t *testing.T) {
	path := filepath.Join("testdata", "test.env")
	src := NewDotEnvSource("test", path, "MORPHIR", 5)

	exists, err := src.Exists()
	if err != nil {
		t.Fatalf("Exists: unexpected error: %v", err)
	}
	if !exists {
		t.Error("Exists: want true for existing file, got false")
	}
}

func TestDotEnvSourceExistsForNonExistingFile(t *testing.T) {
	src := NewDotEnvSource("test", "/nonexistent/.env", "MORPHIR", 5)

	exists, err := src.Exists()
	if err != nil {
		t.Fatalf("Exists: unexpected error: %v", err)
	}
	if exists {
		t.Error("Exists: want false for non-existing file, got true")
	}
}

func TestDotEnvSourceExistsForDirectory(t *testing.T) {
	src := NewDotEnvSource("test", "testdata", "MORPHIR", 5)

	exists, err := src.Exists()
	if err != nil {
		t.Fatalf("Exists: unexpected error: %v", err)
	}
	if exists {
		t.Error("Exists: want false for directory, got true")
	}
}

func TestDotEnvSourceLoadValidFile(t *testing.T) {
	path := filepath.Join("testdata", "test.env")
	src := NewDotEnvSource("test", path, "MORPHIR", 5)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}
	if data == nil {
		t.Fatal("Load: expected non-nil data")
	}

	// Check simple value
	if data["ir_format_version"] != int64(3) {
		t.Errorf("ir_format_version: want 3, got %v", data["ir_format_version"])
	}

	// Check boolean value
	if data["cache_enabled"] != true {
		t.Errorf("cache_enabled: want true, got %v", data["cache_enabled"])
	}

	// Check string value
	if data["logging_level"] != "debug" {
		t.Errorf("logging_level: want debug, got %v", data["logging_level"])
	}

	// Check nested value
	codegen, ok := data["codegen"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen to be a map")
	}

	goSection, ok := codegen["go"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen.go to be a map")
	}

	if goSection["package"] != "morphir" {
		t.Errorf("codegen.go.package: want morphir, got %v", goSection["package"])
	}
}

func TestDotEnvSourceLoadNonExistingFile(t *testing.T) {
	src := NewDotEnvSource("test", "/nonexistent/.env", "MORPHIR", 5)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error for non-existing file: %v", err)
	}
	if data != nil {
		t.Error("Load: want nil data for non-existing file, got non-nil")
	}
}

func TestDotEnvSourceLoadEmptyFile(t *testing.T) {
	// Create a temporary empty file
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, ".env")
	if err := os.WriteFile(path, []byte{}, 0644); err != nil {
		t.Fatalf("failed to create empty file: %v", err)
	}

	src := NewDotEnvSource("test", path, "MORPHIR", 5)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error for empty file: %v", err)
	}
	if data != nil {
		t.Log("Load: empty file returned nil (expected)")
	}
}

func TestDotEnvSourceLoadWithDifferentPrefix(t *testing.T) {
	// Create a temporary .env file with custom prefix
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, ".env")
	content := `MYAPP_DEBUG=true
MYAPP_PORT=8080
MORPHIR_IGNORED=value
`
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatalf("failed to create .env file: %v", err)
	}

	src := NewDotEnvSource("test", path, "MYAPP", 5)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}
	if data == nil {
		t.Fatal("Load: expected non-nil data")
	}

	if data["debug"] != true {
		t.Errorf("debug: want true, got %v", data["debug"])
	}

	if data["port"] != int64(8080) {
		t.Errorf("port: want 8080, got %v", data["port"])
	}

	// MORPHIR_IGNORED should not be present
	if _, ok := data["ignored"]; ok {
		t.Error("Load: MORPHIR_IGNORED should not be present with MYAPP prefix")
	}
}

func TestDotEnvSourceImplementsInterface(t *testing.T) {
	var _ Source = (*DotEnvSource)(nil)
}
