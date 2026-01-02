package workspace

import (
	"path/filepath"
	"testing"
)

func TestWorkspaceRoot(t *testing.T) {
	ws := NewWorkspace("/home/user/project", "/home/user/project/morphir.toml")

	if got := ws.Root(); got != "/home/user/project" {
		t.Errorf("Root: want /home/user/project, got %q", got)
	}
}

func TestWorkspaceConfigPath(t *testing.T) {
	ws := NewWorkspace("/home/user/project", "/home/user/project/morphir.toml")

	if got := ws.ConfigPath(); got != "/home/user/project/morphir.toml" {
		t.Errorf("ConfigPath: want /home/user/project/morphir.toml, got %q", got)
	}
}

func TestWorkspaceMorphirDir(t *testing.T) {
	ws := NewWorkspace("/home/user/project", "/home/user/project/morphir.toml")

	want := filepath.Join("/home/user/project", ".morphir")
	if got := ws.MorphirDir(); got != want {
		t.Errorf("MorphirDir: want %q, got %q", want, got)
	}
}

func TestWorkspaceOutDir(t *testing.T) {
	ws := NewWorkspace("/home/user/project", "/home/user/project/morphir.toml")

	want := filepath.Join("/home/user/project", ".morphir", "out")
	if got := ws.OutDir(); got != want {
		t.Errorf("OutDir: want %q, got %q", want, got)
	}
}

func TestWorkspaceCacheDir(t *testing.T) {
	ws := NewWorkspace("/home/user/project", "/home/user/project/morphir.toml")

	want := filepath.Join("/home/user/project", ".morphir", "cache")
	if got := ws.CacheDir(); got != want {
		t.Errorf("CacheDir: want %q, got %q", want, got)
	}
}

func TestWorkspaceUserConfigPath(t *testing.T) {
	ws := NewWorkspace("/home/user/project", "/home/user/project/morphir.toml")

	want := filepath.Join("/home/user/project", ".morphir", "morphir.user.toml")
	if got := ws.UserConfigPath(); got != want {
		t.Errorf("UserConfigPath: want %q, got %q", want, got)
	}
}

func TestNewWorkspace(t *testing.T) {
	root := "/path/to/workspace"
	configPath := "/path/to/workspace/morphir.toml"

	ws := NewWorkspace(root, configPath)

	if ws.root != root {
		t.Errorf("root: want %q, got %q", root, ws.root)
	}
	if ws.configPath != configPath {
		t.Errorf("configPath: want %q, got %q", configPath, ws.configPath)
	}
}
