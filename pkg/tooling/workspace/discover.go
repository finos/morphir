package workspace

import (
	"os"
	"path/filepath"
)

// Workspace markers in order of preference.
// The first marker found determines the workspace root.
var workspaceMarkers = []string{
	"morphir.toml",          // Preferred: visible config file
	".morphir/morphir.toml", // Alternative: hidden directory with config
	".morphir",              // Minimal: just the directory
}

// DiscoverResult contains the result of workspace discovery.
type DiscoverResult struct {
	workspace *Workspace // The discovered workspace, nil if not found
	searched  []string   // Directories that were searched
}

// Found returns true if a workspace was discovered.
func (r DiscoverResult) Found() bool {
	return r.workspace != nil
}

// Workspace returns the discovered workspace.
// Returns nil if no workspace was found.
func (r DiscoverResult) Workspace() *Workspace {
	return r.workspace
}

// SearchedDirs returns the list of directories that were searched.
// This is useful for debugging or displaying to users.
func (r DiscoverResult) SearchedDirs() []string {
	result := make([]string, len(r.searched))
	copy(result, r.searched)
	return result
}

// Discover searches for a Morphir workspace starting from startDir
// and walking up the directory tree until a workspace marker is found
// or the filesystem root is reached.
//
// Workspace markers are checked in this order:
//  1. morphir.toml (preferred, visible)
//  2. .morphir/morphir.toml (alternative)
//  3. .morphir/ directory (minimal marker)
//
// Returns a DiscoverResult containing the workspace (if found) and
// information about the search.
func Discover(startDir string) (DiscoverResult, error) {
	result := DiscoverResult{
		searched: make([]string, 0),
	}

	// Get absolute path
	absStart, err := filepath.Abs(startDir)
	if err != nil {
		return result, &DiscoverError{
			StartDir: startDir,
			Err:      err,
		}
	}

	// Verify start directory exists
	info, err := os.Stat(absStart)
	if err != nil {
		return result, &DiscoverError{
			StartDir: startDir,
			Err:      err,
		}
	}
	if !info.IsDir() {
		return result, &DiscoverError{
			StartDir: startDir,
			Err:      ErrNotDirectory,
		}
	}

	current := absStart
	for {
		result.searched = append(result.searched, current)

		// Check for workspace markers
		ws, found := checkWorkspaceMarkers(current)
		if found {
			result.workspace = ws
			return result, nil
		}

		// Move to parent directory
		parent := filepath.Dir(current)
		if parent == current {
			// Reached filesystem root
			break
		}
		current = parent
	}

	return result, nil
}

// DiscoverFrom searches for a workspace starting from startDir and returns
// the workspace if found, or an error if not found.
//
// This is a convenience function that wraps Discover and returns an error
// if no workspace is found, rather than returning a result with Found() == false.
func DiscoverFrom(startDir string) (Workspace, error) {
	result, err := Discover(startDir)
	if err != nil {
		return Workspace{}, err
	}

	if !result.Found() {
		return Workspace{}, &NotFoundError{
			StartDir:     startDir,
			SearchedDirs: result.SearchedDirs(),
		}
	}

	return *result.Workspace(), nil
}

// DiscoverFromCwd searches for a workspace starting from the current
// working directory.
func DiscoverFromCwd() (Workspace, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return Workspace{}, &DiscoverError{
			StartDir: ".",
			Err:      err,
		}
	}
	return DiscoverFrom(cwd)
}

// IsWorkspaceRoot checks if the given directory is a workspace root
// (i.e., contains a workspace marker).
func IsWorkspaceRoot(dir string) (bool, error) {
	absDir, err := filepath.Abs(dir)
	if err != nil {
		return false, err
	}

	info, err := os.Stat(absDir)
	if err != nil {
		return false, err
	}
	if !info.IsDir() {
		return false, ErrNotDirectory
	}

	_, found := checkWorkspaceMarkers(absDir)
	return found, nil
}

// checkWorkspaceMarkers checks for workspace markers in the given directory.
// Returns the workspace and true if a marker is found.
func checkWorkspaceMarkers(dir string) (*Workspace, bool) {
	for _, marker := range workspaceMarkers {
		markerPath := filepath.Join(dir, marker)
		info, err := os.Stat(markerPath)
		if err != nil {
			continue
		}

		// For morphir.toml markers, verify it's a file
		switch marker {
		case "morphir.toml", ".morphir/morphir.toml":
			if !info.IsDir() {
				ws := NewWorkspace(dir, markerPath)
				return &ws, true
			}
		case ".morphir":
			// For .morphir directory marker, verify it's a directory
			if info.IsDir() {
				ws := NewWorkspace(dir, markerPath)
				return &ws, true
			}
		}
	}
	return nil, false
}
