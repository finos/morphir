package workspace

import (
	"path/filepath"
	"testing"
)

func TestLoadWorkspaceWithMembers(t *testing.T) {
	// Create workspace structure:
	// root/
	//   morphir.toml (workspace config with members)
	//   packages/
	//     pkg-a/
	//       morphir.toml
	//     pkg-b/
	//       morphir.json
	root := t.TempDir()

	// Create workspace config
	createFile(t, filepath.Join(root, "morphir.toml"), `
[morphir]
version = "^3.0.0"

[workspace]
members = ["packages/*"]
`)

	// Create member packages
	pkgA := filepath.Join(root, "packages", "pkg-a")
	createDir(t, pkgA)
	createFile(t, filepath.Join(pkgA, "morphir.toml"), `
[project]
name = "pkg-a"
source_directory = "src"
exposed_modules = ["Main"]
`)

	pkgB := filepath.Join(root, "packages", "pkg-b")
	createDir(t, pkgB)
	createFile(t, filepath.Join(pkgB, "morphir.json"), `{
		"name": "Pkg.B",
		"sourceDirectory": "lib",
		"exposedModules": ["Core"]
	}`)

	// Load workspace
	lw, err := Load(root)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	// Check members
	members := lw.Members()
	if len(members) != 2 {
		t.Errorf("expected 2 members, got %d", len(members))
	}

	// Check no root project
	if lw.HasRootProject() {
		t.Error("expected no root project for virtual workspace")
	}

	// Check member lookup by name
	pkgAProj, found := lw.MemberByName("pkg-a")
	if !found {
		t.Error("MemberByName(pkg-a) not found")
	} else if pkgAProj.SourceDirectory() != "src" {
		t.Errorf("pkg-a SourceDirectory() = %v, want src", pkgAProj.SourceDirectory())
	}

	pkgBProj, found := lw.MemberByName("Pkg.B")
	if !found {
		t.Error("MemberByName(Pkg.B) not found")
	} else if pkgBProj.SourceDirectory() != "lib" {
		t.Errorf("Pkg.B SourceDirectory() = %v, want lib", pkgBProj.SourceDirectory())
	}
}

func TestLoadWorkspaceWithRootProject(t *testing.T) {
	// Create workspace with both workspace config and project
	root := t.TempDir()

	createFile(t, filepath.Join(root, "morphir.toml"), `
[morphir]
version = "^3.0.0"

[workspace]
members = ["libs/*"]

[project]
name = "my-app"
source_directory = "src"
exposed_modules = ["App"]
module_prefix = "MyApp"
`)

	// Create a lib member
	lib := filepath.Join(root, "libs", "utils")
	createDir(t, lib)
	createFile(t, filepath.Join(lib, "morphir.toml"), `
[project]
name = "utils"
source_directory = "src"
exposed_modules = ["Helpers"]
`)

	lw, err := Load(root)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	// Check root project
	if !lw.HasRootProject() {
		t.Error("expected root project")
	}

	rootProj := lw.RootProject()
	if rootProj.Name() != "my-app" {
		t.Errorf("root project Name() = %v, want my-app", rootProj.Name())
	}
	if rootProj.ModulePrefix() != "MyApp" {
		t.Errorf("root project ModulePrefix() = %v, want MyApp", rootProj.ModulePrefix())
	}

	// Check members
	members := lw.Members()
	if len(members) != 1 {
		t.Errorf("expected 1 member, got %d", len(members))
	}

	// Check AllProjects includes root and members
	all := lw.AllProjects()
	if len(all) != 2 {
		t.Errorf("AllProjects() len = %d, want 2", len(all))
	}
	// Root should be first
	if all[0].Name() != "my-app" {
		t.Errorf("AllProjects()[0] = %v, want my-app", all[0].Name())
	}
}

func TestLoadWorkspaceWithExclude(t *testing.T) {
	root := t.TempDir()

	createFile(t, filepath.Join(root, "morphir.toml"), `
[workspace]
members = ["packages/**"]
exclude = ["**/testdata"]
`)

	// Create packages
	pkg := filepath.Join(root, "packages", "core")
	createDir(t, pkg)
	createFile(t, filepath.Join(pkg, "morphir.toml"), `[project]
name = "core"
source_directory = "src"
exposed_modules = []
`)

	// Create testdata that should be excluded
	testdata := filepath.Join(root, "packages", "testdata")
	createDir(t, testdata)
	createFile(t, filepath.Join(testdata, "morphir.toml"), `[project]
name = "testdata"
source_directory = "src"
exposed_modules = []
`)

	lw, err := Load(root)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	members := lw.Members()
	if len(members) != 1 {
		t.Errorf("expected 1 member (testdata excluded), got %d", len(members))
	}

	if members[0].Name() != "core" {
		t.Errorf("member name = %v, want core", members[0].Name())
	}
}

func TestLoadWorkspaceNoMembers(t *testing.T) {
	root := t.TempDir()

	// Workspace without members array
	createFile(t, filepath.Join(root, "morphir.toml"), `
[morphir]
version = "^3.0.0"
`)

	lw, err := Load(root)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	members := lw.Members()
	if members != nil {
		t.Errorf("expected nil members, got %d", len(members))
	}
}

func TestLoadWorkspaceConfig(t *testing.T) {
	root := t.TempDir()

	createFile(t, filepath.Join(root, "morphir.toml"), `
[morphir]
version = "^3.0.0"

[workspace]
output_dir = "build"

[ir]
format_version = 5
strict_mode = true
`)

	lw, err := Load(root)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	cfg := lw.Config()

	if cfg.Morphir().Version() != "^3.0.0" {
		t.Errorf("Morphir().Version() = %v, want ^3.0.0", cfg.Morphir().Version())
	}
	if cfg.Workspace().OutputDir() != "build" {
		t.Errorf("Workspace().OutputDir() = %v, want build", cfg.Workspace().OutputDir())
	}
	if cfg.IR().FormatVersion() != 5 {
		t.Errorf("IR().FormatVersion() = %v, want 5", cfg.IR().FormatVersion())
	}
	if !cfg.IR().StrictMode() {
		t.Error("IR().StrictMode() = false, want true")
	}
}

func TestLoadWorkspaceMemberByPath(t *testing.T) {
	root := t.TempDir()

	createFile(t, filepath.Join(root, "morphir.toml"), `
[workspace]
members = ["packages/*"]
`)

	pkg := filepath.Join(root, "packages", "mylib")
	createDir(t, pkg)
	createFile(t, filepath.Join(pkg, "morphir.toml"), `[project]
name = "mylib"
source_directory = "src"
exposed_modules = []
`)

	lw, err := Load(root)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	// Look up by path
	proj, found := lw.MemberByPath(pkg)
	if !found {
		t.Error("MemberByPath() not found")
	}
	if proj.Name() != "mylib" {
		t.Errorf("Name() = %v, want mylib", proj.Name())
	}

	// Non-existent path
	_, found = lw.MemberByPath("/nonexistent")
	if found {
		t.Error("MemberByPath(/nonexistent) should not be found")
	}
}

func TestLoadWorkspaceErrors(t *testing.T) {
	root := t.TempDir()

	createFile(t, filepath.Join(root, "morphir.toml"), `
[workspace]
members = ["packages/*"]
`)

	// Create one valid and one invalid package
	valid := filepath.Join(root, "packages", "valid")
	createDir(t, valid)
	createFile(t, filepath.Join(valid, "morphir.toml"), `[project]
name = "valid"
source_directory = "src"
exposed_modules = []
`)

	invalid := filepath.Join(root, "packages", "invalid")
	createDir(t, invalid)
	createFile(t, filepath.Join(invalid, "morphir.json"), `invalid json`)

	lw, err := Load(root)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	// Should have loaded the valid one
	members := lw.Members()
	if len(members) != 1 {
		t.Errorf("expected 1 member, got %d", len(members))
	}

	// Should have recorded the error
	errors := lw.Errors()
	if len(errors) != 1 {
		t.Errorf("expected 1 error, got %d", len(errors))
	}
}

func TestLoadFromSubdirectory(t *testing.T) {
	root := t.TempDir()

	createFile(t, filepath.Join(root, "morphir.toml"), `
[morphir]
version = "^3.0.0"
`)

	// Create a subdirectory
	subDir := filepath.Join(root, "some", "nested", "dir")
	createDir(t, subDir)

	// Load from subdirectory should find workspace at root
	lw, err := Load(subDir)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if lw.Workspace().Root() != root {
		t.Errorf("Workspace().Root() = %v, want %v", lw.Workspace().Root(), root)
	}
}
