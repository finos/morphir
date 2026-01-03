package workspace

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestDiscoverWithMorphirToml(t *testing.T) {
	// Create temp directory structure:
	// tmpDir/
	//   morphir.toml
	//   subdir/
	//     nested/
	tmpDir := t.TempDir()
	createFile(t, filepath.Join(tmpDir, "morphir.toml"), "[morphir]")
	createDir(t, filepath.Join(tmpDir, "subdir", "nested"))

	// Discover from nested directory
	result, err := Discover(filepath.Join(tmpDir, "subdir", "nested"))
	if err != nil {
		t.Fatalf("Discover: unexpected error: %v", err)
	}

	if !result.Found() {
		t.Fatal("expected workspace to be found")
	}

	ws := result.Workspace()
	if ws.Root() != tmpDir {
		t.Errorf("Root: want %q, got %q", tmpDir, ws.Root())
	}
	if ws.ConfigPath() != filepath.Join(tmpDir, "morphir.toml") {
		t.Errorf("ConfigPath: want %q, got %q",
			filepath.Join(tmpDir, "morphir.toml"), ws.ConfigPath())
	}
}

func TestDiscoverWithHiddenMorphirToml(t *testing.T) {
	// Create temp directory structure:
	// tmpDir/
	//   .morphir/
	//     morphir.toml
	//   subdir/
	tmpDir := t.TempDir()
	morphirDir := filepath.Join(tmpDir, ".morphir")
	createDir(t, morphirDir)
	createFile(t, filepath.Join(morphirDir, "morphir.toml"), "[morphir]")
	createDir(t, filepath.Join(tmpDir, "subdir"))

	// Discover from subdir
	result, err := Discover(filepath.Join(tmpDir, "subdir"))
	if err != nil {
		t.Fatalf("Discover: unexpected error: %v", err)
	}

	if !result.Found() {
		t.Fatal("expected workspace to be found")
	}

	ws := result.Workspace()
	if ws.Root() != tmpDir {
		t.Errorf("Root: want %q, got %q", tmpDir, ws.Root())
	}
}

func TestDiscoverWithMorphirDirOnly(t *testing.T) {
	// Create temp directory structure:
	// tmpDir/
	//   .morphir/ (empty directory)
	//   subdir/
	tmpDir := t.TempDir()
	createDir(t, filepath.Join(tmpDir, ".morphir"))
	createDir(t, filepath.Join(tmpDir, "subdir"))

	// Discover from subdir
	result, err := Discover(filepath.Join(tmpDir, "subdir"))
	if err != nil {
		t.Fatalf("Discover: unexpected error: %v", err)
	}

	if !result.Found() {
		t.Fatal("expected workspace to be found")
	}

	ws := result.Workspace()
	if ws.Root() != tmpDir {
		t.Errorf("Root: want %q, got %q", tmpDir, ws.Root())
	}
}

func TestDiscoverPrefersMorphirToml(t *testing.T) {
	// Create temp directory structure with both markers:
	// tmpDir/
	//   morphir.toml (should be preferred)
	//   .morphir/
	//     morphir.toml
	tmpDir := t.TempDir()
	createFile(t, filepath.Join(tmpDir, "morphir.toml"), "[morphir]")
	morphirDir := filepath.Join(tmpDir, ".morphir")
	createDir(t, morphirDir)
	createFile(t, filepath.Join(morphirDir, "morphir.toml"), "[morphir]")

	result, err := Discover(tmpDir)
	if err != nil {
		t.Fatalf("Discover: unexpected error: %v", err)
	}

	if !result.Found() {
		t.Fatal("expected workspace to be found")
	}

	ws := result.Workspace()
	// Should prefer morphir.toml over .morphir/morphir.toml
	if ws.ConfigPath() != filepath.Join(tmpDir, "morphir.toml") {
		t.Errorf("ConfigPath: want %q (preferred), got %q",
			filepath.Join(tmpDir, "morphir.toml"), ws.ConfigPath())
	}
}

func TestDiscoverNotFound(t *testing.T) {
	// Create temp directory with no markers
	tmpDir := t.TempDir()
	createDir(t, filepath.Join(tmpDir, "subdir"))

	result, err := Discover(filepath.Join(tmpDir, "subdir"))
	if err != nil {
		t.Fatalf("Discover: unexpected error: %v", err)
	}

	if result.Found() {
		t.Error("expected workspace not to be found")
	}

	// Should have searched at least 2 directories (subdir and tmpDir)
	if len(result.SearchedDirs()) < 2 {
		t.Errorf("expected at least 2 searched dirs, got %d", len(result.SearchedDirs()))
	}
}

func TestDiscoverFromNotFound(t *testing.T) {
	tmpDir := t.TempDir()

	_, err := DiscoverFrom(tmpDir)
	if err == nil {
		t.Fatal("expected error, got nil")
	}

	var notFoundErr *NotFoundError
	if !errors.As(err, &notFoundErr) {
		t.Errorf("expected NotFoundError, got %T", err)
	}
}

func TestDiscoverNonExistentDirectory(t *testing.T) {
	_, err := Discover("/nonexistent/path/that/does/not/exist")
	if err == nil {
		t.Fatal("expected error for non-existent directory")
	}

	var discoverErr *DiscoverError
	if !errors.As(err, &discoverErr) {
		t.Errorf("expected DiscoverError, got %T", err)
	}
}

func TestDiscoverFromFile(t *testing.T) {
	tmpDir := t.TempDir()
	filePath := filepath.Join(tmpDir, "somefile.txt")
	createFile(t, filePath, "content")

	_, err := Discover(filePath)
	if err == nil {
		t.Fatal("expected error when discovering from a file")
	}

	var discoverErr *DiscoverError
	if !errors.As(err, &discoverErr) {
		t.Errorf("expected DiscoverError, got %T", err)
	}

	if !errors.Is(discoverErr.Err, ErrNotDirectory) {
		t.Errorf("expected ErrNotDirectory, got %v", discoverErr.Err)
	}
}

func TestIsWorkspaceRoot(t *testing.T) {
	tests := []struct {
		name     string
		setup    func(t *testing.T, dir string)
		wantRoot bool
	}{
		{
			name: "with morphir.toml",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "morphir.toml"), "[morphir]")
			},
			wantRoot: true,
		},
		{
			name: "with .morphir/morphir.toml",
			setup: func(t *testing.T, dir string) {
				morphirDir := filepath.Join(dir, ".morphir")
				createDir(t, morphirDir)
				createFile(t, filepath.Join(morphirDir, "morphir.toml"), "[morphir]")
			},
			wantRoot: true,
		},
		{
			name: "with .morphir directory only",
			setup: func(t *testing.T, dir string) {
				createDir(t, filepath.Join(dir, ".morphir"))
			},
			wantRoot: true,
		},
		{
			name:     "empty directory",
			setup:    func(t *testing.T, dir string) {},
			wantRoot: false,
		},
		{
			name: "with unrelated files",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "README.md"), "# Project")
				createFile(t, filepath.Join(dir, "go.mod"), "module example")
			},
			wantRoot: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			tt.setup(t, tmpDir)

			isRoot, err := IsWorkspaceRoot(tmpDir)
			if err != nil {
				t.Fatalf("IsWorkspaceRoot: unexpected error: %v", err)
			}

			if isRoot != tt.wantRoot {
				t.Errorf("IsWorkspaceRoot: want %v, got %v", tt.wantRoot, isRoot)
			}
		})
	}
}

func TestIsWorkspaceRootNonExistent(t *testing.T) {
	_, err := IsWorkspaceRoot("/nonexistent/path")
	if err == nil {
		t.Fatal("expected error for non-existent path")
	}
}

func TestIsWorkspaceRootNotDirectory(t *testing.T) {
	tmpDir := t.TempDir()
	filePath := filepath.Join(tmpDir, "file.txt")
	createFile(t, filePath, "content")

	_, err := IsWorkspaceRoot(filePath)
	if err == nil {
		t.Fatal("expected error for file path")
	}

	if !errors.Is(err, ErrNotDirectory) {
		t.Errorf("expected ErrNotDirectory, got %v", err)
	}
}

func TestDiscoverResultSearchedDirsDefensiveCopy(t *testing.T) {
	tmpDir := t.TempDir()

	result, err := Discover(tmpDir)
	if err != nil {
		t.Fatalf("Discover: unexpected error: %v", err)
	}

	dirs1 := result.SearchedDirs()
	dirs2 := result.SearchedDirs()

	// Modify the first slice
	if len(dirs1) > 0 {
		dirs1[0] = "modified"
	}

	// Second slice should be unaffected
	if len(dirs2) > 0 && dirs2[0] == "modified" {
		t.Error("SearchedDirs should return a defensive copy")
	}
}

func TestDiscoverMultipleLevels(t *testing.T) {
	// Create a deep directory structure:
	// tmpDir/
	//   morphir.toml
	//   a/
	//     b/
	//       c/
	//         d/
	tmpDir := t.TempDir()
	createFile(t, filepath.Join(tmpDir, "morphir.toml"), "[morphir]")
	deepDir := filepath.Join(tmpDir, "a", "b", "c", "d")
	createDir(t, deepDir)

	result, err := Discover(deepDir)
	if err != nil {
		t.Fatalf("Discover: unexpected error: %v", err)
	}

	if !result.Found() {
		t.Fatal("expected workspace to be found")
	}

	// Should have searched: d, c, b, a, tmpDir
	if len(result.SearchedDirs()) != 5 {
		t.Errorf("expected 5 searched dirs, got %d: %v",
			len(result.SearchedDirs()), result.SearchedDirs())
	}

	if result.Workspace().Root() != tmpDir {
		t.Errorf("Root: want %q, got %q", tmpDir, result.Workspace().Root())
	}
}

// Helper functions

func createDir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0755); err != nil {
		t.Fatalf("failed to create directory %q: %v", path, err)
	}
}

func createFile(t *testing.T, path string, content string) {
	t.Helper()
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatalf("failed to create directory %q: %v", dir, err)
	}
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatalf("failed to create file %q: %v", path, err)
	}
}
