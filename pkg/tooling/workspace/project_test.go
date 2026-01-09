package workspace

import (
	"path/filepath"
	"testing"
)

func TestLoadProjectFromTOML(t *testing.T) {
	tmpDir := t.TempDir()

	// Create a project with morphir.toml
	projDir := filepath.Join(tmpDir, "my-project")
	createDir(t, projDir)
	createFile(t, filepath.Join(projDir, "morphir.toml"), `
[project]
name = "my-project"
version = "1.0.0"
source_directory = "src"
exposed_modules = ["Main", "Utils"]
module_prefix = "MyProject"
`)

	proj, err := LoadProject(projDir)
	if err != nil {
		t.Fatalf("LoadProject() error = %v", err)
	}

	if proj.Name() != "my-project" {
		t.Errorf("Name() = %v, want my-project", proj.Name())
	}
	if proj.Version() != "1.0.0" {
		t.Errorf("Version() = %v, want 1.0.0", proj.Version())
	}
	if proj.SourceDirectory() != "src" {
		t.Errorf("SourceDirectory() = %v, want src", proj.SourceDirectory())
	}
	if proj.ModulePrefix() != "MyProject" {
		t.Errorf("ModulePrefix() = %v, want MyProject", proj.ModulePrefix())
	}
	if proj.ConfigFormat() != "toml" {
		t.Errorf("ConfigFormat() = %v, want toml", proj.ConfigFormat())
	}

	mods := proj.ExposedModules()
	if len(mods) != 2 || mods[0] != "Main" || mods[1] != "Utils" {
		t.Errorf("ExposedModules() = %v, want [Main Utils]", mods)
	}

	expectedAbsSrc := filepath.Join(projDir, "src")
	if proj.AbsSourceDirectory() != expectedAbsSrc {
		t.Errorf("AbsSourceDirectory() = %v, want %v", proj.AbsSourceDirectory(), expectedAbsSrc)
	}
}

func TestLoadProjectFromJSON(t *testing.T) {
	tmpDir := t.TempDir()

	// Create a project with morphir.json
	projDir := filepath.Join(tmpDir, "elm-project")
	createDir(t, projDir)
	createFile(t, filepath.Join(projDir, "morphir.json"), `{
		"name": "My.Elm.Package",
		"sourceDirectory": "src",
		"exposedModules": ["Foo", "Bar"]
	}`)

	proj, err := LoadProject(projDir)
	if err != nil {
		t.Fatalf("LoadProject() error = %v", err)
	}

	if proj.Name() != "My.Elm.Package" {
		t.Errorf("Name() = %v, want My.Elm.Package", proj.Name())
	}
	if proj.SourceDirectory() != "src" {
		t.Errorf("SourceDirectory() = %v, want src", proj.SourceDirectory())
	}
	// For morphir.json, module_prefix should equal name
	if proj.ModulePrefix() != "My.Elm.Package" {
		t.Errorf("ModulePrefix() = %v, want My.Elm.Package", proj.ModulePrefix())
	}
	if proj.ConfigFormat() != "json" {
		t.Errorf("ConfigFormat() = %v, want json", proj.ConfigFormat())
	}

	mods := proj.ExposedModules()
	if len(mods) != 2 || mods[0] != "Foo" || mods[1] != "Bar" {
		t.Errorf("ExposedModules() = %v, want [Foo Bar]", mods)
	}
}

func TestLoadProjectFromHiddenTOML(t *testing.T) {
	tmpDir := t.TempDir()

	// Create a project with .morphir/morphir.toml
	projDir := filepath.Join(tmpDir, "hidden-config")
	createDir(t, filepath.Join(projDir, ".morphir"))
	createFile(t, filepath.Join(projDir, ".morphir", "morphir.toml"), `
[project]
name = "hidden-project"
source_directory = "lib"
exposed_modules = ["Core"]
`)

	proj, err := LoadProject(projDir)
	if err != nil {
		t.Fatalf("LoadProject() error = %v", err)
	}

	if proj.Name() != "hidden-project" {
		t.Errorf("Name() = %v, want hidden-project", proj.Name())
	}
	if proj.SourceDirectory() != "lib" {
		t.Errorf("SourceDirectory() = %v, want lib", proj.SourceDirectory())
	}
}

func TestLoadProjectNoConfig(t *testing.T) {
	tmpDir := t.TempDir()

	// Create an empty directory
	projDir := filepath.Join(tmpDir, "no-config")
	createDir(t, projDir)

	_, err := LoadProject(projDir)
	if err == nil {
		t.Fatal("LoadProject() expected error for missing config")
	}
}

func TestLoadProjectPrefersTOMLOverJSON(t *testing.T) {
	tmpDir := t.TempDir()

	// Create a project with both morphir.toml and morphir.json
	projDir := filepath.Join(tmpDir, "dual-config")
	createDir(t, projDir)
	createFile(t, filepath.Join(projDir, "morphir.toml"), `
[project]
name = "from-toml"
source_directory = "src"
exposed_modules = []
`)
	createFile(t, filepath.Join(projDir, "morphir.json"), `{
		"name": "from-json",
		"sourceDirectory": "lib",
		"exposedModules": []
	}`)

	proj, err := LoadProject(projDir)
	if err != nil {
		t.Fatalf("LoadProject() error = %v", err)
	}

	// Should prefer TOML
	if proj.Name() != "from-toml" {
		t.Errorf("Name() = %v, want from-toml (should prefer TOML)", proj.Name())
	}
	if proj.ConfigFormat() != "toml" {
		t.Errorf("ConfigFormat() = %v, want toml", proj.ConfigFormat())
	}
}

func TestLoadProjects(t *testing.T) {
	tmpDir := t.TempDir()

	// Create multiple projects
	proj1 := filepath.Join(tmpDir, "pkg1")
	proj2 := filepath.Join(tmpDir, "pkg2")
	proj3 := filepath.Join(tmpDir, "invalid")

	createDir(t, proj1)
	createFile(t, filepath.Join(proj1, "morphir.toml"), `[project]
name = "pkg1"
source_directory = "src"
exposed_modules = []
`)

	createDir(t, proj2)
	createFile(t, filepath.Join(proj2, "morphir.json"), `{"name": "pkg2", "sourceDirectory": "src", "exposedModules": []}`)

	createDir(t, proj3)
	// No config file - should fail

	projects, errors := LoadProjects([]string{proj1, proj2, proj3})

	if len(projects) != 2 {
		t.Errorf("expected 2 projects, got %d", len(projects))
	}
	if len(errors) != 1 {
		t.Errorf("expected 1 error, got %d", len(errors))
	}

	// Check project names
	names := make(map[string]bool)
	for _, p := range projects {
		names[p.Name()] = true
	}
	if !names["pkg1"] || !names["pkg2"] {
		t.Errorf("expected pkg1 and pkg2, got %v", names)
	}
}

func TestProjectPath(t *testing.T) {
	tmpDir := t.TempDir()

	projDir := filepath.Join(tmpDir, "test-path")
	createDir(t, projDir)
	createFile(t, filepath.Join(projDir, "morphir.toml"), `[project]
name = "test"
source_directory = "src"
exposed_modules = []
`)

	proj, err := LoadProject(projDir)
	if err != nil {
		t.Fatalf("LoadProject() error = %v", err)
	}

	if proj.Path() != projDir {
		t.Errorf("Path() = %v, want %v", proj.Path(), projDir)
	}

	expectedConfigPath := filepath.Join(projDir, "morphir.toml")
	if proj.ConfigPath() != expectedConfigPath {
		t.Errorf("ConfigPath() = %v, want %v", proj.ConfigPath(), expectedConfigPath)
	}
}

func TestLoadProjectWithDecorationsFromTOML(t *testing.T) {
	tmpDir := t.TempDir()

	projDir := filepath.Join(tmpDir, "decorated-project")
	createDir(t, projDir)
	createFile(t, filepath.Join(projDir, "morphir.toml"), `
[project]
name = "decorated-project"
source_directory = "src"
exposed_modules = ["Main"]

[project.decorations.myDecoration]
display_name = "My Amazing Decoration"
ir = "decorations/my/morphir-ir.json"
entry_point = "My.Amazing.Decoration:Foo:Shape"
storage_location = "my-decoration-values.json"

[project.decorations.anotherDec]
display_name = "Another Decoration"
ir = "decorations/another/ir.json"
entry_point = "Another:Module:Type"
storage_location = "another-values.json"
`)

	proj, err := LoadProject(projDir)
	if err != nil {
		t.Fatalf("LoadProject() error = %v", err)
	}

	if proj.Name() != "decorated-project" {
		t.Errorf("Name() = %v, want decorated-project", proj.Name())
	}

	decorations := proj.Decorations()
	if len(decorations) != 2 {
		t.Fatalf("Decorations() len = %d, want 2", len(decorations))
	}

	dec, ok := decorations["myDecoration"]
	if !ok {
		t.Fatal("expected myDecoration to be found")
	}
	if dec.DisplayName() != "My Amazing Decoration" {
		t.Errorf("DisplayName() = %v, want My Amazing Decoration", dec.DisplayName())
	}
	if dec.IR() != "decorations/my/morphir-ir.json" {
		t.Errorf("IR() = %v, want decorations/my/morphir-ir.json", dec.IR())
	}
	if dec.EntryPoint() != "My.Amazing.Decoration:Foo:Shape" {
		t.Errorf("EntryPoint() = %v, want My.Amazing.Decoration:Foo:Shape", dec.EntryPoint())
	}
	if dec.StorageLocation() != "my-decoration-values.json" {
		t.Errorf("StorageLocation() = %v, want my-decoration-values.json", dec.StorageLocation())
	}
}

func TestLoadProjectWithDecorationsFromJSON(t *testing.T) {
	tmpDir := t.TempDir()

	projDir := filepath.Join(tmpDir, "json-decorated-project")
	createDir(t, projDir)
	createFile(t, filepath.Join(projDir, "morphir.json"), `{
		"name": "My.Elm.Package",
		"sourceDirectory": "src",
		"exposedModules": ["Foo"],
		"decorations": {
			"myDecoration": {
				"displayName": "My Amazing Decoration",
				"ir": "decorations/my/morphir-ir.json",
				"entryPoint": "My.Amazing.Decoration:Foo:Shape",
				"storageLocation": "my-decoration-values.json"
			}
		}
	}`)

	proj, err := LoadProject(projDir)
	if err != nil {
		t.Fatalf("LoadProject() error = %v", err)
	}

	if proj.Name() != "My.Elm.Package" {
		t.Errorf("Name() = %v, want My.Elm.Package", proj.Name())
	}

	decorations := proj.Decorations()
	if len(decorations) != 1 {
		t.Fatalf("Decorations() len = %d, want 1", len(decorations))
	}

	dec, ok := decorations["myDecoration"]
	if !ok {
		t.Fatal("expected myDecoration to be found")
	}
	if dec.DisplayName() != "My Amazing Decoration" {
		t.Errorf("DisplayName() = %v, want My Amazing Decoration", dec.DisplayName())
	}
}

func TestLoadProjectWithoutDecorations(t *testing.T) {
	tmpDir := t.TempDir()

	projDir := filepath.Join(tmpDir, "no-decorations")
	createDir(t, projDir)
	createFile(t, filepath.Join(projDir, "morphir.toml"), `
[project]
name = "simple-project"
source_directory = "src"
exposed_modules = ["Main"]
`)

	proj, err := LoadProject(projDir)
	if err != nil {
		t.Fatalf("LoadProject() error = %v", err)
	}

	decorations := proj.Decorations()
	if decorations != nil {
		t.Errorf("expected nil decorations, got %v", decorations)
	}
}
