// Package workspace provides functionality for discovering and working with
// Morphir workspaces. A workspace is a directory containing a morphir.toml
// configuration file.
package workspace

import (
	"path/filepath"
)

// Workspace represents a discovered Morphir workspace.
// It provides access to important paths within the workspace.
type Workspace struct {
	root       string // Absolute path to workspace root
	configPath string // Path to the configuration file that marked this workspace
}

// Root returns the absolute path to the workspace root directory.
func (w Workspace) Root() string {
	return w.root
}

// ConfigPath returns the path to the configuration file that was used
// to identify this workspace (e.g., morphir.toml or .morphir/morphir.toml).
func (w Workspace) ConfigPath() string {
	return w.configPath
}

// MorphirDir returns the path to the .morphir directory within the workspace.
// This directory contains outputs, cache, and user overrides.
func (w Workspace) MorphirDir() string {
	return filepath.Join(w.root, ".morphir")
}

// OutDir returns the default output directory for generated artifacts.
// This is .morphir/out by default but may be overridden by configuration.
func (w Workspace) OutDir() string {
	return filepath.Join(w.root, ".morphir", "out")
}

// CacheDir returns the path to the cache directory within the workspace.
func (w Workspace) CacheDir() string {
	return filepath.Join(w.root, ".morphir", "cache")
}

// UserConfigPath returns the path to the user override configuration file.
// This file is typically gitignored and contains user-specific settings.
func (w Workspace) UserConfigPath() string {
	return filepath.Join(w.root, ".morphir", "morphir.user.toml")
}

// NewWorkspace creates a new Workspace with the given root and config path.
// Both paths should be absolute. This is primarily used internally by
// the discovery functions.
func NewWorkspace(root, configPath string) Workspace {
	return Workspace{
		root:       root,
		configPath: configPath,
	}
}
