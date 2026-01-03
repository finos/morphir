package configloader

import (
	"path/filepath"

	"github.com/finos/morphir-go/pkg/config/internal/sources"
	"github.com/finos/morphir-go/pkg/config/internal/xdg"
)

// Priority constants define the loading order for configuration sources.
// Higher priority values override lower priority values.
const (
	PriorityBuiltinDefaults = 0
	PrioritySystem          = 100
	PriorityGlobal          = 200
	PriorityProject         = 300
	PriorityUserOverride    = 400
	PriorityEnvFile         = 500
	PriorityEnvVar          = 600
)

// SourceInfo tracks information about a configuration source.
type SourceInfo struct {
	Name     string // Source name (e.g., "defaults", "system", "global", "project")
	Path     string // File path or identifier
	Priority int    // Priority level
	Loaded   bool   // Whether the source was successfully loaded
	Error    error  // Error if loading failed
}

// LoadResult contains the merged configuration and source metadata.
type LoadResult struct {
	Config  map[string]any // Merged configuration
	Sources []SourceInfo   // Information about each source
}

// LoaderOptions configures the Loader behavior.
type LoaderOptions struct {
	// WorkDir is the working directory for project config discovery.
	// Defaults to current working directory.
	WorkDir string

	// SystemConfigDir overrides the system config directory.
	// Defaults to /etc on Unix, %PROGRAMDATA% on Windows.
	SystemConfigDir string

	// GlobalConfigDir overrides the global user config directory.
	// Defaults to ~/.config/morphir on Unix, %APPDATA%/morphir on Windows.
	GlobalConfigDir string

	// EnvPrefix is the prefix for environment variables.
	// Defaults to "MORPHIR".
	EnvPrefix string

	// SkipSystem disables loading system configuration.
	SkipSystem bool

	// SkipGlobal disables loading global user configuration.
	SkipGlobal bool

	// SkipProject disables loading project configuration.
	SkipProject bool

	// SkipUser disables loading user override configuration.
	SkipUser bool

	// SkipEnv disables loading environment variables.
	SkipEnv bool
}

// Loader orchestrates configuration loading from multiple sources.
type Loader struct {
	opts LoaderOptions
	xdg  *xdg.Paths
}

// NewLoader creates a new Loader with the given options.
func NewLoader(opts LoaderOptions) *Loader {
	if opts.EnvPrefix == "" {
		opts.EnvPrefix = "MORPHIR"
	}
	return &Loader{
		opts: opts,
		xdg:  xdg.New(),
	}
}

// Load loads configuration from all sources and merges them.
func (l *Loader) Load() (LoadResult, error) {
	result := LoadResult{
		Sources: make([]SourceInfo, 0),
	}

	// Collect all configuration maps to merge
	configs := make([]map[string]any, 0)

	// 1. Built-in defaults (always loaded)
	defaults := DefaultValues()
	configs = append(configs, defaults)
	result.Sources = append(result.Sources, SourceInfo{
		Name:     "defaults",
		Path:     "(built-in)",
		Priority: PriorityBuiltinDefaults,
		Loaded:   true,
	})

	// 2. System configuration
	if !l.opts.SkipSystem {
		systemPath := l.systemConfigPath()
		info := l.loadTOMLSource("system", systemPath, PrioritySystem)
		result.Sources = append(result.Sources, info)
		if info.Loaded {
			src := sources.NewTOMLSource("system", systemPath, PrioritySystem)
			if data, err := src.Load(); err == nil && data != nil {
				configs = append(configs, data)
			}
		}
	}

	// 3. Global user configuration
	if !l.opts.SkipGlobal {
		globalPath := l.globalConfigPath()
		info := l.loadTOMLSource("global", globalPath, PriorityGlobal)
		result.Sources = append(result.Sources, info)
		if info.Loaded {
			src := sources.NewTOMLSource("global", globalPath, PriorityGlobal)
			if data, err := src.Load(); err == nil && data != nil {
				configs = append(configs, data)
			}
		}
	}

	// 4. Project configuration
	if !l.opts.SkipProject {
		projectPath := l.projectConfigPath()
		info := l.loadTOMLSource("project", projectPath, PriorityProject)
		result.Sources = append(result.Sources, info)
		if info.Loaded {
			src := sources.NewTOMLSource("project", projectPath, PriorityProject)
			if data, err := src.Load(); err == nil && data != nil {
				configs = append(configs, data)
			}
		}
	}

	// 5. User override configuration
	if !l.opts.SkipUser {
		userPath := l.userConfigPath()
		info := l.loadTOMLSource("user", userPath, PriorityUserOverride)
		result.Sources = append(result.Sources, info)
		if info.Loaded {
			src := sources.NewTOMLSource("user", userPath, PriorityUserOverride)
			if data, err := src.Load(); err == nil && data != nil {
				configs = append(configs, data)
			}
		}
	}

	// 6. Environment variables
	if !l.opts.SkipEnv {
		envSrc := sources.NewEnvSource(l.opts.EnvPrefix, PriorityEnvVar)
		data, err := envSrc.Load()
		info := SourceInfo{
			Name:     "env",
			Path:     envSrc.Path(),
			Priority: PriorityEnvVar,
			Loaded:   data != nil,
			Error:    err,
		}
		result.Sources = append(result.Sources, info)
		if data != nil {
			configs = append(configs, data)
		}
	}

	// Merge all configurations
	result.Config = MergeAll(configs...)

	return result, nil
}

// loadTOMLSource checks if a TOML file exists and returns source info.
func (l *Loader) loadTOMLSource(name, path string, priority int) SourceInfo {
	src := sources.NewTOMLSource(name, path, priority)
	exists, err := src.Exists()

	return SourceInfo{
		Name:     name,
		Path:     path,
		Priority: priority,
		Loaded:   exists && err == nil,
		Error:    err,
	}
}

// systemConfigPath returns the system configuration file path.
func (l *Loader) systemConfigPath() string {
	if l.opts.SystemConfigDir != "" {
		return filepath.Join(l.opts.SystemConfigDir, "morphir", "morphir.toml")
	}
	return l.xdg.SystemConfigFile()
}

// globalConfigPath returns the global user configuration file path.
func (l *Loader) globalConfigPath() string {
	if l.opts.GlobalConfigDir != "" {
		return filepath.Join(l.opts.GlobalConfigDir, "morphir.toml")
	}
	return l.xdg.GlobalConfigFile()
}

// projectConfigPath returns the project configuration file path.
func (l *Loader) projectConfigPath() string {
	workDir := l.opts.WorkDir
	if workDir == "" {
		workDir = "."
	}
	return filepath.Join(workDir, "morphir.toml")
}

// userConfigPath returns the user override configuration file path.
func (l *Loader) userConfigPath() string {
	workDir := l.opts.WorkDir
	if workDir == "" {
		workDir = "."
	}
	return filepath.Join(workDir, ".morphir", "morphir.user.toml")
}
