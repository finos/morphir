package workspace

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInitDefaultOptions(t *testing.T) {
	tmpDir := t.TempDir()

	result, err := Init(InitOptions{Path: tmpDir})
	if err != nil {
		t.Fatalf("Init: unexpected error: %v", err)
	}

	// Check workspace was created
	ws := result.Workspace()
	if ws.Root() != tmpDir {
		t.Errorf("Root: want %q, got %q", tmpDir, ws.Root())
	}

	// Config should be in root (default style)
	expectedConfigPath := filepath.Join(tmpDir, "morphir.toml")
	if ws.ConfigPath() != expectedConfigPath {
		t.Errorf("ConfigPath: want %q, got %q", expectedConfigPath, ws.ConfigPath())
	}

	// Check morphir.toml exists and has correct content
	content, err := os.ReadFile(expectedConfigPath)
	if err != nil {
		t.Fatalf("failed to read morphir.toml: %v", err)
	}
	if !strings.Contains(string(content), filepath.Base(tmpDir)) {
		t.Errorf("morphir.toml should contain project name %q", filepath.Base(tmpDir))
	}

	// Check .morphir directory exists
	morphirDir := filepath.Join(tmpDir, ".morphir")
	if !dirExists(t, morphirDir) {
		t.Error(".morphir directory should exist")
	}

	// Check subdirectories exist
	if !dirExists(t, filepath.Join(morphirDir, "out")) {
		t.Error(".morphir/out directory should exist")
	}
	if !dirExists(t, filepath.Join(morphirDir, "cache")) {
		t.Error(".morphir/cache directory should exist")
	}

	// Check .gitignore exists
	gitignorePath := filepath.Join(morphirDir, ".gitignore")
	if !fileExists(t, gitignorePath) {
		t.Error(".morphir/.gitignore should exist")
	}
}

func TestInitWithCustomName(t *testing.T) {
	tmpDir := t.TempDir()

	result, err := Init(InitOptions{
		Path: tmpDir,
		Name: "my-project",
	})
	if err != nil {
		t.Fatalf("Init: unexpected error: %v", err)
	}

	content, err := os.ReadFile(result.Workspace().ConfigPath())
	if err != nil {
		t.Fatalf("failed to read morphir.toml: %v", err)
	}
	if !strings.Contains(string(content), `name = "my-project"`) {
		t.Errorf("morphir.toml should contain name = \"my-project\", got:\n%s", content)
	}
}

func TestInitHiddenStyle(t *testing.T) {
	tmpDir := t.TempDir()

	result, err := Init(InitOptions{
		Path:  tmpDir,
		Style: ConfigStyleHidden,
	})
	if err != nil {
		t.Fatalf("Init: unexpected error: %v", err)
	}

	// Config should be in .morphir directory
	expectedConfigPath := filepath.Join(tmpDir, ".morphir", "morphir.toml")
	if result.Workspace().ConfigPath() != expectedConfigPath {
		t.Errorf("ConfigPath: want %q, got %q", expectedConfigPath, result.Workspace().ConfigPath())
	}

	// Verify file exists
	if !fileExists(t, expectedConfigPath) {
		t.Error(".morphir/morphir.toml should exist")
	}
}

func TestInitRootStyle(t *testing.T) {
	tmpDir := t.TempDir()

	result, err := Init(InitOptions{
		Path:  tmpDir,
		Style: ConfigStyleRoot,
	})
	if err != nil {
		t.Fatalf("Init: unexpected error: %v", err)
	}

	// Config should be in root directory
	expectedConfigPath := filepath.Join(tmpDir, "morphir.toml")
	if result.Workspace().ConfigPath() != expectedConfigPath {
		t.Errorf("ConfigPath: want %q, got %q", expectedConfigPath, result.Workspace().ConfigPath())
	}
}

func TestInitCreatedFilesTracking(t *testing.T) {
	tmpDir := t.TempDir()

	result, err := Init(InitOptions{Path: tmpDir})
	if err != nil {
		t.Fatalf("Init: unexpected error: %v", err)
	}

	// Should have created files
	files := result.CreatedFiles()
	if len(files) < 2 {
		t.Errorf("expected at least 2 created files, got %d", len(files))
	}

	// Should have created directories
	dirs := result.CreatedDirs()
	if len(dirs) < 3 {
		t.Errorf("expected at least 3 created dirs, got %d", len(dirs))
	}
}

func TestInitGitignoreContent(t *testing.T) {
	tmpDir := t.TempDir()

	_, err := Init(InitOptions{Path: tmpDir})
	if err != nil {
		t.Fatalf("Init: unexpected error: %v", err)
	}

	content, err := os.ReadFile(filepath.Join(tmpDir, ".morphir", ".gitignore"))
	if err != nil {
		t.Fatalf("failed to read .gitignore: %v", err)
	}

	expectedPatterns := []string{
		"morphir.user.toml",
		".env",
		"out/",
		"cache/",
		"state/",
		"logs/",
		"*.tmp",
	}

	for _, pattern := range expectedPatterns {
		if !strings.Contains(string(content), pattern) {
			t.Errorf(".gitignore should contain %q", pattern)
		}
	}
}

func TestInitIdempotent(t *testing.T) {
	tmpDir := t.TempDir()

	// First init
	_, err := Init(InitOptions{Path: tmpDir})
	if err != nil {
		t.Fatalf("first Init: unexpected error: %v", err)
	}

	// Second init should fail with AlreadyExistsError
	_, err = Init(InitOptions{Path: tmpDir})
	if err == nil {
		t.Fatal("second Init should fail")
	}

	var alreadyExists *AlreadyExistsError
	if !errors.As(err, &alreadyExists) {
		t.Errorf("expected AlreadyExistsError, got %T: %v", err, err)
	}
}

func TestInitInSubdirectory(t *testing.T) {
	tmpDir := t.TempDir()

	// First init at root
	_, err := Init(InitOptions{Path: tmpDir})
	if err != nil {
		t.Fatalf("first Init: unexpected error: %v", err)
	}

	// Create subdirectory
	subDir := filepath.Join(tmpDir, "subdir")
	if err := os.MkdirAll(subDir, 0755); err != nil {
		t.Fatalf("failed to create subdir: %v", err)
	}

	// Init in subdirectory should fail (already in workspace)
	_, err = Init(InitOptions{Path: subDir})
	if err == nil {
		t.Fatal("Init in subdirectory of existing workspace should fail")
	}

	var alreadyExists *AlreadyExistsError
	if !errors.As(err, &alreadyExists) {
		t.Errorf("expected AlreadyExistsError, got %T: %v", err, err)
	}
}

func TestInitNonExistentPath(t *testing.T) {
	_, err := Init(InitOptions{Path: "/nonexistent/path/that/does/not/exist"})
	if err == nil {
		t.Fatal("Init with non-existent path should fail")
	}

	var initErr *InitError
	if !errors.As(err, &initErr) {
		t.Errorf("expected InitError, got %T: %v", err, err)
	}

	if !errors.Is(initErr.Err, ErrPathNotExist) {
		t.Errorf("expected ErrPathNotExist, got %v", initErr.Err)
	}
}

func TestInitOnFile(t *testing.T) {
	tmpDir := t.TempDir()
	filePath := filepath.Join(tmpDir, "file.txt")
	if err := os.WriteFile(filePath, []byte("content"), 0644); err != nil {
		t.Fatalf("failed to create file: %v", err)
	}

	_, err := Init(InitOptions{Path: filePath})
	if err == nil {
		t.Fatal("Init on file should fail")
	}

	var initErr *InitError
	if !errors.As(err, &initErr) {
		t.Errorf("expected InitError, got %T: %v", err, err)
	}

	if !errors.Is(initErr.Err, ErrNotDirectory) {
		t.Errorf("expected ErrNotDirectory, got %v", initErr.Err)
	}
}

func TestInitResultDefensiveCopy(t *testing.T) {
	tmpDir := t.TempDir()

	result, err := Init(InitOptions{Path: tmpDir})
	if err != nil {
		t.Fatalf("Init: unexpected error: %v", err)
	}

	// Get files twice
	files1 := result.CreatedFiles()
	files2 := result.CreatedFiles()

	// Modify first slice
	if len(files1) > 0 {
		files1[0] = "modified"
	}

	// Second slice should be unaffected
	if len(files2) > 0 && files2[0] == "modified" {
		t.Error("CreatedFiles should return a defensive copy")
	}

	// Same for dirs
	dirs1 := result.CreatedDirs()
	dirs2 := result.CreatedDirs()

	if len(dirs1) > 0 {
		dirs1[0] = "modified"
	}

	if len(dirs2) > 0 && dirs2[0] == "modified" {
		t.Error("CreatedDirs should return a defensive copy")
	}
}

func TestMorphirTomlContent(t *testing.T) {
	content := morphirTomlContent("test-project")

	if !strings.Contains(content, "[morphir]") {
		t.Error("should contain [morphir] section")
	}
	if !strings.Contains(content, `name = "test-project"`) {
		t.Errorf("should contain name = \"test-project\", got:\n%s", content)
	}
}

func TestGitignoreContentFunction(t *testing.T) {
	content := gitignoreContent()

	// Should end with newline
	if !strings.HasSuffix(content, "\n") {
		t.Error("gitignore content should end with newline")
	}

	// Should contain expected patterns
	if !strings.Contains(content, "morphir.user.toml") {
		t.Error("should contain morphir.user.toml")
	}
}

// Helper functions

func dirExists(t *testing.T, path string) bool {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return info.IsDir()
}

func fileExists(t *testing.T, path string) bool {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir()
}
