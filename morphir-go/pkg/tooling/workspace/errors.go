package workspace

import (
	"errors"
	"fmt"
	"strings"
)

// Sentinel errors for workspace operations.
var (
	// ErrNotDirectory is returned when a path is expected to be a directory
	// but is not.
	ErrNotDirectory = errors.New("path is not a directory")

	// ErrPathNotExist is returned when a path does not exist.
	ErrPathNotExist = errors.New("path does not exist")

	// ErrNoProjectConfig is returned when a directory has no project configuration.
	ErrNoProjectConfig = errors.New("no project configuration found")

	// ErrUnknownConfigFormat is returned when a configuration file has an unknown format.
	ErrUnknownConfigFormat = errors.New("unknown configuration format")
)

// DiscoverError represents an error that occurred during workspace discovery.
type DiscoverError struct {
	StartDir string // The directory where discovery started
	Err      error  // The underlying error
}

// Error returns the error message.
func (e *DiscoverError) Error() string {
	return fmt.Sprintf("failed to discover workspace from %q: %v", e.StartDir, e.Err)
}

// Unwrap returns the underlying error.
func (e *DiscoverError) Unwrap() error {
	return e.Err
}

// NotFoundError is returned when no workspace is found after searching
// from a starting directory to the filesystem root.
type NotFoundError struct {
	StartDir     string   // The directory where search started
	SearchedDirs []string // All directories that were searched
}

// Error returns the error message.
func (e *NotFoundError) Error() string {
	return fmt.Sprintf("no morphir workspace found (searched %d directories from %q)",
		len(e.SearchedDirs), e.StartDir)
}

// Is allows errors.Is to match NotFoundError.
func (e *NotFoundError) Is(target error) bool {
	_, ok := target.(*NotFoundError)
	return ok
}

// Detail returns a detailed message about the search that was performed.
func (e *NotFoundError) Detail() string {
	var b strings.Builder
	b.WriteString(fmt.Sprintf("No Morphir workspace found.\n\nSearched %d directories:\n",
		len(e.SearchedDirs)))
	for _, dir := range e.SearchedDirs {
		b.WriteString(fmt.Sprintf("  - %s\n", dir))
	}
	b.WriteString("\nTo create a workspace, run: morphir init\n")
	return b.String()
}

// InitError represents an error that occurred during workspace initialization.
type InitError struct {
	Path string // The path where initialization was attempted
	Err  error  // The underlying error
}

// Error returns the error message.
func (e *InitError) Error() string {
	return fmt.Sprintf("failed to initialize workspace at %q: %v", e.Path, e.Err)
}

// Unwrap returns the underlying error.
func (e *InitError) Unwrap() error {
	return e.Err
}

// AlreadyExistsError is returned when trying to initialize a workspace
// in a directory that is already part of a workspace.
type AlreadyExistsError struct {
	ExistingRoot string // The root of the existing workspace
}

// Error returns the error message.
func (e *AlreadyExistsError) Error() string {
	return fmt.Sprintf("workspace already exists at %q", e.ExistingRoot)
}

// Is allows errors.Is to match AlreadyExistsError.
func (e *AlreadyExistsError) Is(target error) bool {
	_, ok := target.(*AlreadyExistsError)
	return ok
}

// ProjectLoadError represents an error that occurred while loading a project.
type ProjectLoadError struct {
	Path string // The path to the project
	Err  error  // The underlying error
}

// Error returns the error message.
func (e *ProjectLoadError) Error() string {
	return fmt.Sprintf("failed to load project at %q: %v", e.Path, e.Err)
}

// Unwrap returns the underlying error.
func (e *ProjectLoadError) Unwrap() error {
	return e.Err
}
