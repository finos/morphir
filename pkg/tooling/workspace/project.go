package workspace

import (
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
	"github.com/finos/morphir/pkg/config"
)

// Project represents a loaded workspace member project.
// It contains the project configuration and its location within the workspace.
type Project struct {
	path          string                // Absolute path to project directory
	configPath    string                // Path to the config file (morphir.toml or morphir.json)
	configFormat  string                // "toml" or "json"
	projectConfig config.ProjectSection // The loaded project configuration
}

// Path returns the absolute path to the project directory.
func (p Project) Path() string {
	return p.path
}

// ConfigPath returns the path to the project's configuration file.
func (p Project) ConfigPath() string {
	return p.configPath
}

// ConfigFormat returns the format of the configuration file ("toml" or "json").
func (p Project) ConfigFormat() string {
	return p.configFormat
}

// Name returns the project name.
func (p Project) Name() string {
	return p.projectConfig.Name()
}

// Version returns the project version.
func (p Project) Version() string {
	return p.projectConfig.Version()
}

// SourceDirectory returns the source directory path (relative to project path).
func (p Project) SourceDirectory() string {
	return p.projectConfig.SourceDirectory()
}

// AbsSourceDirectory returns the absolute path to the source directory.
func (p Project) AbsSourceDirectory() string {
	return filepath.Join(p.path, p.projectConfig.SourceDirectory())
}

// ExposedModules returns the list of exposed modules.
func (p Project) ExposedModules() []string {
	return p.projectConfig.ExposedModules()
}

// ModulePrefix returns the module prefix for Elm-style qualified names.
func (p Project) ModulePrefix() string {
	return p.projectConfig.ModulePrefix()
}

// Decorations returns the decoration configurations for this project.
func (p Project) Decorations() map[string]config.DecorationConfig {
	return p.projectConfig.Decorations()
}

// Config returns the underlying ProjectSection configuration.
func (p Project) Config() config.ProjectSection {
	return p.projectConfig
}

// LoadProject loads a project from the given directory.
// It auto-detects the configuration format (TOML or JSON).
func LoadProject(dir string) (Project, error) {
	absDir, err := filepath.Abs(dir)
	if err != nil {
		return Project{}, err
	}

	configPath, format, found := FindProjectConfig(absDir)
	if !found {
		return Project{}, &ProjectLoadError{
			Path: absDir,
			Err:  ErrNoProjectConfig,
		}
	}

	var projectConfig config.ProjectSection

	switch format {
	case "toml":
		projectConfig, err = loadProjectFromTOML(configPath)
	case "json":
		projectConfig, err = loadProjectFromJSON(configPath)
	default:
		return Project{}, &ProjectLoadError{
			Path: absDir,
			Err:  ErrUnknownConfigFormat,
		}
	}

	if err != nil {
		return Project{}, &ProjectLoadError{
			Path: absDir,
			Err:  err,
		}
	}

	return Project{
		path:          absDir,
		configPath:    configPath,
		configFormat:  format,
		projectConfig: projectConfig,
	}, nil
}

// loadProjectFromTOML loads project configuration from a TOML file.
func loadProjectFromTOML(path string) (config.ProjectSection, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return config.ProjectSection{}, err
	}

	var raw map[string]any
	if err := toml.Unmarshal(data, &raw); err != nil {
		return config.ProjectSection{}, err
	}

	cfg := config.FromMap(raw)
	return cfg.Project(), nil
}

// loadProjectFromJSON loads project configuration from a morphir.json file.
func loadProjectFromJSON(path string) (config.ProjectSection, error) {
	m, err := config.LoadMorphirJSON(path)
	if err != nil {
		return config.ProjectSection{}, err
	}
	return m.ToProjectSection(), nil
}

// LoadProjects loads all projects from the given paths.
// Returns the successfully loaded projects and any errors encountered.
func LoadProjects(paths []string) ([]Project, []error) {
	projects := make([]Project, 0, len(paths))
	var errors []error

	for _, path := range paths {
		project, err := LoadProject(path)
		if err != nil {
			errors = append(errors, err)
			continue
		}
		projects = append(projects, project)
	}

	return projects, errors
}

// NewProject creates a Project with the given parameters.
// This is primarily for testing purposes.
func NewProject(path, configPath, configFormat string, projectConfig config.ProjectSection) Project {
	return Project{
		path:          path,
		configPath:    configPath,
		configFormat:  configFormat,
		projectConfig: projectConfig,
	}
}
