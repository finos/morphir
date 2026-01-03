package workspace

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ConfigStyle determines where the morphir.toml file is placed.
type ConfigStyle string

const (
	// ConfigStyleRoot places morphir.toml in the project root.
	ConfigStyleRoot ConfigStyle = "root"
	// ConfigStyleHidden places morphir.toml inside .morphir/ directory.
	ConfigStyleHidden ConfigStyle = "hidden"
)

// InitOptions configures workspace initialization.
type InitOptions struct {
	// Path is the directory where the workspace will be created.
	// Defaults to the current working directory.
	Path string

	// Name is the project name used in morphir.toml.
	// Defaults to the directory name.
	Name string

	// Style determines where morphir.toml is placed.
	// Defaults to ConfigStyleRoot.
	Style ConfigStyle
}

// InitResult contains information about the initialized workspace.
type InitResult struct {
	workspace    Workspace
	createdFiles []string
	createdDirs  []string
}

// Workspace returns the initialized workspace.
func (r InitResult) Workspace() Workspace {
	return r.workspace
}

// CreatedFiles returns a list of files that were created.
func (r InitResult) CreatedFiles() []string {
	result := make([]string, len(r.createdFiles))
	copy(result, r.createdFiles)
	return result
}

// CreatedDirs returns a list of directories that were created.
func (r InitResult) CreatedDirs() []string {
	result := make([]string, len(r.createdDirs))
	copy(result, r.createdDirs)
	return result
}

// Init initializes a new Morphir workspace at the specified path.
// It creates the morphir.toml configuration file and the .morphir directory
// structure with appropriate subdirectories.
func Init(opts InitOptions) (InitResult, error) {
	result := InitResult{
		createdFiles: make([]string, 0),
		createdDirs:  make([]string, 0),
	}

	// Resolve path
	path := opts.Path
	if path == "" {
		var err error
		path, err = os.Getwd()
		if err != nil {
			return result, &InitError{Path: ".", Err: err}
		}
	}

	// Ensure path exists
	absPath, err := filepath.Abs(path)
	if err != nil {
		return result, &InitError{Path: path, Err: err}
	}

	info, err := os.Stat(absPath)
	if err != nil {
		if os.IsNotExist(err) {
			return result, &InitError{Path: absPath, Err: ErrPathNotExist}
		}
		return result, &InitError{Path: absPath, Err: err}
	}
	if !info.IsDir() {
		return result, &InitError{Path: absPath, Err: ErrNotDirectory}
	}

	// Resolve project name
	name := opts.Name
	if name == "" {
		name = filepath.Base(absPath)
	}

	// Determine config style
	style := opts.Style
	if style == "" {
		style = ConfigStyleRoot
	}

	// Check if workspace already exists
	existingResult, err := Discover(absPath)
	if err != nil {
		return result, &InitError{Path: absPath, Err: err}
	}
	if existingResult.Found() {
		return result, &InitError{
			Path: absPath,
			Err:  &AlreadyExistsError{ExistingRoot: existingResult.Workspace().Root()},
		}
	}

	// Create .morphir directory
	morphirDir := filepath.Join(absPath, ".morphir")
	if err := mkdirIfNotExist(morphirDir, &result.createdDirs); err != nil {
		return result, &InitError{Path: absPath, Err: err}
	}

	// Create subdirectories
	subdirs := []string{"out", "cache"}
	for _, subdir := range subdirs {
		dir := filepath.Join(morphirDir, subdir)
		if err := mkdirIfNotExist(dir, &result.createdDirs); err != nil {
			return result, &InitError{Path: absPath, Err: err}
		}
	}

	// Create .gitignore
	gitignorePath := filepath.Join(morphirDir, ".gitignore")
	if err := writeFileIfNotExist(gitignorePath, gitignoreContent(), &result.createdFiles); err != nil {
		return result, &InitError{Path: absPath, Err: err}
	}

	// Create morphir.toml
	var configPath string
	if style == ConfigStyleHidden {
		configPath = filepath.Join(morphirDir, "morphir.toml")
	} else {
		configPath = filepath.Join(absPath, "morphir.toml")
	}
	if err := writeFileIfNotExist(configPath, morphirTomlContent(name), &result.createdFiles); err != nil {
		return result, &InitError{Path: absPath, Err: err}
	}

	result.workspace = NewWorkspace(absPath, configPath)
	return result, nil
}

// mkdirIfNotExist creates a directory if it doesn't exist and tracks it.
func mkdirIfNotExist(path string, created *[]string) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		if err := os.MkdirAll(path, 0755); err != nil {
			return err
		}
		*created = append(*created, path)
	}
	return nil
}

// writeFileIfNotExist creates a file if it doesn't exist and tracks it.
func writeFileIfNotExist(path string, content string, created *[]string) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			return err
		}
		*created = append(*created, path)
	}
	return nil
}

// gitignoreContent returns the content for .morphir/.gitignore.
func gitignoreContent() string {
	lines := []string{
		"# User-specific configuration (not committed)",
		"morphir.user.toml",
		"",
		"# Environment files",
		".env",
		"",
		"# Build outputs",
		"out/",
		"",
		"# Cache files",
		"cache/",
		"",
		"# Runtime state",
		"state/",
		"",
		"# Log files",
		"logs/",
		"",
		"# Temporary files",
		"*.tmp",
	}
	return strings.Join(lines, "\n") + "\n"
}

// morphirTomlContent returns the content for morphir.toml.
func morphirTomlContent(name string) string {
	return fmt.Sprintf(`# Morphir project configuration
# See: https://morphir.finos.org/

[morphir]
name = %q
`, name)
}
