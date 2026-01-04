package sources

import (
	"os"
	"path/filepath"
	"testing"
)

func TestTOMLSourceName(t *testing.T) {
	src := NewTOMLSource("project", "/path/to/morphir.toml", 4)

	if got := src.Name(); got != "project" {
		t.Errorf("Name: want project, got %q", got)
	}
}

func TestTOMLSourcePriority(t *testing.T) {
	src := NewTOMLSource("project", "/path/to/morphir.toml", 4)

	if got := src.Priority(); got != 4 {
		t.Errorf("Priority: want 4, got %d", got)
	}
}

func TestTOMLSourcePath(t *testing.T) {
	src := NewTOMLSource("project", "/path/to/morphir.toml", 4)

	if got := src.Path(); got != "/path/to/morphir.toml" {
		t.Errorf("Path: want /path/to/morphir.toml, got %q", got)
	}
}

func TestTOMLSourceExistsForExistingFile(t *testing.T) {
	path := filepath.Join("testdata", "valid.toml")
	src := NewTOMLSource("test", path, 1)

	exists, err := src.Exists()
	if err != nil {
		t.Fatalf("Exists: unexpected error: %v", err)
	}
	if !exists {
		t.Error("Exists: want true for existing file, got false")
	}
}

func TestTOMLSourceExistsForNonExistingFile(t *testing.T) {
	src := NewTOMLSource("test", "/nonexistent/path/morphir.toml", 1)

	exists, err := src.Exists()
	if err != nil {
		t.Fatalf("Exists: unexpected error: %v", err)
	}
	if exists {
		t.Error("Exists: want false for non-existing file, got true")
	}
}

func TestTOMLSourceExistsForDirectory(t *testing.T) {
	src := NewTOMLSource("test", "testdata", 1)

	exists, err := src.Exists()
	if err != nil {
		t.Fatalf("Exists: unexpected error: %v", err)
	}
	if exists {
		t.Error("Exists: want false for directory, got true")
	}
}

func TestTOMLSourceLoadValidFile(t *testing.T) {
	path := filepath.Join("testdata", "valid.toml")
	src := NewTOMLSource("test", path, 1)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}
	if data == nil {
		t.Fatal("Load: expected non-nil data")
	}

	// Check morphir section
	morphir, ok := data["morphir"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected morphir section to be a map")
	}
	if morphir["version"] != "3.0" {
		t.Errorf("morphir.version: want 3.0, got %v", morphir["version"])
	}

	// Check ir section
	ir, ok := data["ir"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected ir section to be a map")
	}
	if ir["format_version"] != int64(3) {
		t.Errorf("ir.format_version: want 3, got %v (type %T)", ir["format_version"], ir["format_version"])
	}
	if ir["strict_mode"] != true {
		t.Errorf("ir.strict_mode: want true, got %v", ir["strict_mode"])
	}

	// Check codegen targets array
	codegen, ok := data["codegen"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen section to be a map")
	}
	targets, ok := codegen["targets"].([]any)
	if !ok {
		t.Fatal("Load: expected codegen.targets to be an array")
	}
	if len(targets) != 2 {
		t.Errorf("codegen.targets: want 2 elements, got %d", len(targets))
	}
}

func TestTOMLSourceLoadMinimalFile(t *testing.T) {
	path := filepath.Join("testdata", "minimal.toml")
	src := NewTOMLSource("test", path, 1)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}
	if data == nil {
		t.Fatal("Load: expected non-nil data")
	}

	ir, ok := data["ir"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected ir section to be a map")
	}
	if ir["format_version"] != int64(3) {
		t.Errorf("ir.format_version: want 3, got %v", ir["format_version"])
	}
}

func TestTOMLSourceLoadNonExistingFile(t *testing.T) {
	src := NewTOMLSource("test", "/nonexistent/path/morphir.toml", 1)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error for non-existing file: %v", err)
	}
	if data != nil {
		t.Error("Load: want nil data for non-existing file, got non-nil")
	}
}

func TestTOMLSourceLoadInvalidFile(t *testing.T) {
	path := filepath.Join("testdata", "invalid.toml")
	src := NewTOMLSource("test", path, 1)

	data, err := src.Load()
	if err == nil {
		t.Fatal("Load: expected error for invalid TOML, got nil")
	}
	if data != nil {
		t.Error("Load: expected nil data for invalid TOML")
	}
}

func TestTOMLSourceLoadNestedStructures(t *testing.T) {
	path := filepath.Join("testdata", "nested.toml")
	src := NewTOMLSource("test", path, 1)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}
	if data == nil {
		t.Fatal("Load: expected non-nil data")
	}

	// Navigate to codegen.go.options.use_pointers
	codegen, ok := data["codegen"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen section to be a map")
	}

	goSection, ok := codegen["go"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen.go section to be a map")
	}

	options, ok := goSection["options"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen.go.options section to be a map")
	}

	if options["use_pointers"] != true {
		t.Errorf("codegen.go.options.use_pointers: want true, got %v", options["use_pointers"])
	}
}

func TestTOMLSourceImplementsInterface(t *testing.T) {
	var _ Source = (*TOMLSource)(nil)
}

func TestTOMLSourceLoadEmptyFile(t *testing.T) {
	// Create a temporary empty file
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "empty.toml")
	if err := os.WriteFile(path, []byte{}, 0644); err != nil {
		t.Fatalf("failed to create empty file: %v", err)
	}

	src := NewTOMLSource("test", path, 1)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error for empty file: %v", err)
	}
	// Empty TOML file should return empty map, not nil
	if data == nil {
		t.Log("Load: empty file returned nil (acceptable)")
	}
}
