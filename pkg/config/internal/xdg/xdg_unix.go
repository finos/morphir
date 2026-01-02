//go:build !windows

package xdg

import (
	"path/filepath"
)

// configHome returns the XDG config home directory.
// Uses $XDG_CONFIG_HOME if set, otherwise ~/.config
func (p *Paths) configHome() string {
	if dir := p.getenv("XDG_CONFIG_HOME"); dir != "" {
		return dir
	}
	home, err := p.homeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".config")
}

// cacheHome returns the XDG cache home directory.
// Uses $XDG_CACHE_HOME if set, otherwise ~/.cache
func (p *Paths) cacheHome() string {
	if dir := p.getenv("XDG_CACHE_HOME"); dir != "" {
		return dir
	}
	home, err := p.homeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".cache")
}

// dataHome returns the XDG data home directory.
// Uses $XDG_DATA_HOME if set, otherwise ~/.local/share
func (p *Paths) dataHome() string {
	if dir := p.getenv("XDG_DATA_HOME"); dir != "" {
		return dir
	}
	home, err := p.homeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".local", "share")
}

// systemConfigDir returns the system configuration directory.
// On Unix-like systems, this is /etc
func (p *Paths) systemConfigDir() string {
	return "/etc"
}

// isWindows returns false on Unix-like systems.
func (p *Paths) isWindows() bool {
	return false
}
