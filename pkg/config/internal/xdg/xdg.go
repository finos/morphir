// Package xdg provides platform-specific path resolution for configuration,
// cache, and data directories following the XDG Base Directory Specification
// on Unix-like systems and appropriate conventions on Windows.
//
// This package is internal and should not be imported by external code.
// Use the public config package API instead.
package xdg

import (
	"os"
	"path/filepath"
)

const (
	// AppName is the application name used in path construction.
	AppName = "morphir"
)

// Paths provides methods for resolving platform-specific directories.
type Paths struct {
	// getenv allows injection of environment variable lookup for testing.
	getenv func(string) string

	// homeDir allows injection of home directory lookup for testing.
	homeDir func() (string, error)
}

// New creates a new Paths instance using the real environment.
func New() *Paths {
	return &Paths{
		getenv:  os.Getenv,
		homeDir: os.UserHomeDir,
	}
}

// newWithEnv creates a Paths instance with custom environment lookup for testing.
func newWithEnv(getenv func(string) string, homeDir func() (string, error)) *Paths {
	return &Paths{
		getenv:  getenv,
		homeDir: homeDir,
	}
}

// ConfigHome returns the base directory for user-specific configuration files.
// On Unix: $XDG_CONFIG_HOME or ~/.config
// On Windows: %APPDATA%
func (p *Paths) ConfigHome() string {
	return p.configHome()
}

// CacheHome returns the base directory for user-specific cache files.
// On Unix: $XDG_CACHE_HOME or ~/.cache
// On Windows: %LOCALAPPDATA%
func (p *Paths) CacheHome() string {
	return p.cacheHome()
}

// DataHome returns the base directory for user-specific data files.
// On Unix: $XDG_DATA_HOME or ~/.local/share
// On Windows: %LOCALAPPDATA%
func (p *Paths) DataHome() string {
	return p.dataHome()
}

// SystemConfigDir returns the system-wide configuration directory.
// On Unix: /etc
// On Windows: %PROGRAMDATA%
func (p *Paths) SystemConfigDir() string {
	return p.systemConfigDir()
}

// MorphirConfigHome returns the Morphir-specific user configuration directory.
// On Unix: $XDG_CONFIG_HOME/morphir or ~/.config/morphir
// On Windows: %APPDATA%/morphir
func (p *Paths) MorphirConfigHome() string {
	return filepath.Join(p.ConfigHome(), AppName)
}

// MorphirCacheHome returns the Morphir-specific cache directory.
// On Unix: $XDG_CACHE_HOME/morphir or ~/.cache/morphir
// On Windows: %LOCALAPPDATA%/morphir/cache
func (p *Paths) MorphirCacheHome() string {
	base := p.CacheHome()
	// On Windows, add "cache" subdirectory for clarity
	if p.isWindows() {
		return filepath.Join(base, AppName, "cache")
	}
	return filepath.Join(base, AppName)
}

// MorphirDataHome returns the Morphir-specific data directory.
// On Unix: $XDG_DATA_HOME/morphir or ~/.local/share/morphir
// On Windows: %LOCALAPPDATA%/morphir
func (p *Paths) MorphirDataHome() string {
	return filepath.Join(p.DataHome(), AppName)
}

// MorphirSystemConfig returns the system-wide Morphir configuration directory.
// On Unix: /etc/morphir
// On Windows: %PROGRAMDATA%/morphir
func (p *Paths) MorphirSystemConfig() string {
	return filepath.Join(p.SystemConfigDir(), AppName)
}

// GlobalConfigFile returns the path to the global user configuration file.
// On Unix: ~/.config/morphir/morphir.toml
// On Windows: %APPDATA%/morphir/morphir.toml
func (p *Paths) GlobalConfigFile() string {
	return filepath.Join(p.MorphirConfigHome(), "morphir.toml")
}

// SystemConfigFile returns the path to the system-wide configuration file.
// On Unix: /etc/morphir/morphir.toml
// On Windows: %PROGRAMDATA%/morphir/morphir.toml
func (p *Paths) SystemConfigFile() string {
	return filepath.Join(p.MorphirSystemConfig(), "morphir.toml")
}
