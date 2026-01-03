package workspace

import (
	"os"

	"github.com/BurntSushi/toml"
	"github.com/finos/morphir-go/pkg/config"
)

// LoadedWorkspace represents a fully loaded workspace with its configuration
// and discovered member projects.
type LoadedWorkspace struct {
	workspace Workspace     // The basic workspace information
	config    config.Config // The loaded workspace configuration
	members   []Project     // Loaded member projects
	rootProj  *Project      // Root project if workspace has [project] section
	errors    []error       // Errors encountered during member loading
}

// Workspace returns the underlying workspace.
func (lw LoadedWorkspace) Workspace() Workspace {
	return lw.workspace
}

// Config returns the workspace configuration.
func (lw LoadedWorkspace) Config() config.Config {
	return lw.config
}

// Members returns the loaded member projects.
// Returns a defensive copy to preserve immutability.
func (lw LoadedWorkspace) Members() []Project {
	if len(lw.members) == 0 {
		return nil
	}
	result := make([]Project, len(lw.members))
	copy(result, lw.members)
	return result
}

// RootProject returns the root project if the workspace has a [project] section.
// Returns nil if the workspace is a virtual workspace (no root project).
func (lw LoadedWorkspace) RootProject() *Project {
	return lw.rootProj
}

// HasRootProject returns true if the workspace has a [project] section.
func (lw LoadedWorkspace) HasRootProject() bool {
	return lw.rootProj != nil
}

// Errors returns any errors encountered during member loading.
// Returns a defensive copy to preserve immutability.
func (lw LoadedWorkspace) Errors() []error {
	if len(lw.errors) == 0 {
		return nil
	}
	result := make([]error, len(lw.errors))
	copy(result, lw.errors)
	return result
}

// MemberByName finds a member project by name.
// Returns the project and true if found, or zero value and false if not.
func (lw LoadedWorkspace) MemberByName(name string) (Project, bool) {
	for _, m := range lw.members {
		if m.Name() == name {
			return m, true
		}
	}
	return Project{}, false
}

// MemberByPath finds a member project by its path.
// Returns the project and true if found, or zero value and false if not.
func (lw LoadedWorkspace) MemberByPath(path string) (Project, bool) {
	for _, m := range lw.members {
		if m.Path() == path {
			return m, true
		}
	}
	return Project{}, false
}

// AllProjects returns all projects in the workspace, including the root project
// if present. The root project is listed first if it exists.
func (lw LoadedWorkspace) AllProjects() []Project {
	var all []Project
	if lw.rootProj != nil {
		all = append(all, *lw.rootProj)
	}
	all = append(all, lw.members...)
	return all
}

// Load discovers and loads a workspace from the given start directory.
// It loads the workspace configuration, discovers members, and loads their configs.
func Load(startDir string) (LoadedWorkspace, error) {
	// Discover the workspace
	ws, err := DiscoverFrom(startDir)
	if err != nil {
		return LoadedWorkspace{}, err
	}

	return LoadWorkspace(ws)
}

// LoadWorkspace loads configuration and members for an already discovered workspace.
func LoadWorkspace(ws Workspace) (LoadedWorkspace, error) {
	result := LoadedWorkspace{
		workspace: ws,
	}

	// Load workspace configuration
	cfg, err := loadWorkspaceConfig(ws.ConfigPath())
	if err != nil {
		return result, err
	}
	result.config = cfg

	// Check if workspace has a root project
	if cfg.Project().Name() != "" {
		rootProj := NewProject(
			ws.Root(),
			ws.ConfigPath(),
			"toml",
			cfg.Project(),
		)
		result.rootProj = &rootProj
	}

	// Discover and load member projects
	memberPatterns := cfg.Workspace().Members()
	excludePatterns := cfg.Workspace().Exclude()

	if len(memberPatterns) > 0 {
		memberPaths, err := DiscoverMembers(ws.Root(), memberPatterns, excludePatterns)
		if err != nil {
			result.errors = append(result.errors, err)
		} else {
			projects, loadErrors := LoadProjects(memberPaths)
			result.members = projects
			result.errors = append(result.errors, loadErrors...)
		}
	}

	return result, nil
}

// loadWorkspaceConfig loads configuration from a workspace config file.
func loadWorkspaceConfig(configPath string) (config.Config, error) {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return config.Default(), err
	}

	var raw map[string]any
	if err := toml.Unmarshal(data, &raw); err != nil {
		return config.Default(), err
	}

	return config.FromMap(raw), nil
}

// LoadFromCwd discovers and loads a workspace from the current working directory.
func LoadFromCwd() (LoadedWorkspace, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return LoadedWorkspace{}, &DiscoverError{
			StartDir: ".",
			Err:      err,
		}
	}
	return Load(cwd)
}
