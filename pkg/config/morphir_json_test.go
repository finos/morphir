package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseMorphirJSON_Valid(t *testing.T) {
	tests := []struct {
		name     string
		json     string
		wantName string
		wantSrc  string
		wantMods []string
	}{
		{
			name:     "basic config",
			json:     `{"name": "My.Package", "sourceDirectory": "src", "exposedModules": ["Foo", "Bar"]}`,
			wantName: "My.Package",
			wantSrc:  "src",
			wantMods: []string{"Foo", "Bar"},
		},
		{
			name:     "single module",
			json:     `{"name": "Simple", "sourceDirectory": "lib", "exposedModules": ["Main"]}`,
			wantName: "Simple",
			wantSrc:  "lib",
			wantMods: []string{"Main"},
		},
		{
			name:     "empty modules array",
			json:     `{"name": "NoModules", "sourceDirectory": "src", "exposedModules": []}`,
			wantName: "NoModules",
			wantSrc:  "src",
			wantMods: nil,
		},
		{
			name:     "missing exposedModules field",
			json:     `{"name": "NoModulesField", "sourceDirectory": "src"}`,
			wantName: "NoModulesField",
			wantSrc:  "src",
			wantMods: nil,
		},
		{
			name:     "dotted package name",
			json:     `{"name": "Morphir.Reference.Model", "sourceDirectory": "example", "exposedModules": ["BooksAndRecords"]}`,
			wantName: "Morphir.Reference.Model",
			wantSrc:  "example",
			wantMods: []string{"BooksAndRecords"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseMorphirJSON([]byte(tt.json))
			if err != nil {
				t.Fatalf("ParseMorphirJSON() error = %v", err)
			}

			if got.Name() != tt.wantName {
				t.Errorf("Name() = %v, want %v", got.Name(), tt.wantName)
			}
			if got.SourceDirectory() != tt.wantSrc {
				t.Errorf("SourceDirectory() = %v, want %v", got.SourceDirectory(), tt.wantSrc)
			}

			mods := got.ExposedModules()
			if len(mods) != len(tt.wantMods) {
				t.Errorf("ExposedModules() len = %d, want %d", len(mods), len(tt.wantMods))
			} else {
				for i, mod := range mods {
					if mod != tt.wantMods[i] {
						t.Errorf("ExposedModules()[%d] = %v, want %v", i, mod, tt.wantMods[i])
					}
				}
			}
		})
	}
}

func TestParseMorphirJSON_Invalid(t *testing.T) {
	tests := []struct {
		name    string
		json    string
		wantErr error
	}{
		{
			name:    "empty name",
			json:    `{"name": "", "sourceDirectory": "src", "exposedModules": []}`,
			wantErr: ErrMorphirJSONEmptyName,
		},
		{
			name:    "missing name",
			json:    `{"sourceDirectory": "src", "exposedModules": []}`,
			wantErr: ErrMorphirJSONEmptyName,
		},
		{
			name:    "empty sourceDirectory",
			json:    `{"name": "Test", "sourceDirectory": "", "exposedModules": []}`,
			wantErr: ErrMorphirJSONEmptySourceDirectory,
		},
		{
			name:    "missing sourceDirectory",
			json:    `{"name": "Test", "exposedModules": []}`,
			wantErr: ErrMorphirJSONEmptySourceDirectory,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseMorphirJSON([]byte(tt.json))
			if err == nil {
				t.Fatal("ParseMorphirJSON() expected error, got nil")
			}
			if err != tt.wantErr {
				t.Errorf("ParseMorphirJSON() error = %v, want %v", err, tt.wantErr)
			}
		})
	}
}

func TestParseMorphirJSON_InvalidJSON(t *testing.T) {
	tests := []struct {
		name string
		json string
	}{
		{
			name: "malformed JSON",
			json: `{"name": "Test"`,
		},
		{
			name: "not JSON object",
			json: `["array", "not", "object"]`,
		},
		{
			name: "empty string",
			json: ``,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseMorphirJSON([]byte(tt.json))
			if err == nil {
				t.Fatal("ParseMorphirJSON() expected JSON parse error, got nil")
			}
		})
	}
}

func TestLoadMorphirJSON(t *testing.T) {
	// Create temp file with valid content
	tmpDir := t.TempDir()
	jsonPath := filepath.Join(tmpDir, "morphir.json")
	content := `{"name": "Test.Package", "sourceDirectory": "src", "exposedModules": ["Main"]}`

	if err := os.WriteFile(jsonPath, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to write test file: %v", err)
	}

	got, err := LoadMorphirJSON(jsonPath)
	if err != nil {
		t.Fatalf("LoadMorphirJSON() error = %v", err)
	}

	if got.Name() != "Test.Package" {
		t.Errorf("Name() = %v, want Test.Package", got.Name())
	}
	if got.SourceDirectory() != "src" {
		t.Errorf("SourceDirectory() = %v, want src", got.SourceDirectory())
	}
}

func TestLoadMorphirJSON_FileNotFound(t *testing.T) {
	_, err := LoadMorphirJSON("/nonexistent/path/morphir.json")
	if err == nil {
		t.Fatal("LoadMorphirJSON() expected error for non-existent file")
	}
}

func TestMorphirJSON_ToProjectSection(t *testing.T) {
	json := `{"name": "My.Package", "sourceDirectory": "src", "exposedModules": ["Foo", "Bar"]}`
	m, err := ParseMorphirJSON([]byte(json))
	if err != nil {
		t.Fatalf("ParseMorphirJSON() error = %v", err)
	}

	proj := m.ToProjectSection()

	if proj.Name() != "My.Package" {
		t.Errorf("Name() = %v, want My.Package", proj.Name())
	}
	if proj.SourceDirectory() != "src" {
		t.Errorf("SourceDirectory() = %v, want src", proj.SourceDirectory())
	}
	if proj.ModulePrefix() != "My.Package" {
		t.Errorf("ModulePrefix() = %v, want My.Package", proj.ModulePrefix())
	}
	if proj.Version() != "" {
		t.Errorf("Version() = %v, want empty string", proj.Version())
	}

	mods := proj.ExposedModules()
	if len(mods) != 2 {
		t.Errorf("ExposedModules() len = %d, want 2", len(mods))
	}
	if mods[0] != "Foo" || mods[1] != "Bar" {
		t.Errorf("ExposedModules() = %v, want [Foo, Bar]", mods)
	}
}

func TestMorphirJSON_ExposedModulesDefensiveCopy(t *testing.T) {
	json := `{"name": "Test", "sourceDirectory": "src", "exposedModules": ["A", "B"]}`
	m, err := ParseMorphirJSON([]byte(json))
	if err != nil {
		t.Fatalf("ParseMorphirJSON() error = %v", err)
	}

	// Get modules and modify the returned slice
	mods := m.ExposedModules()
	mods[0] = "Modified"

	// Get again and verify original is unchanged
	modsAgain := m.ExposedModules()
	if modsAgain[0] != "A" {
		t.Errorf("ExposedModules() was modified: got %v, want A", modsAgain[0])
	}
}
