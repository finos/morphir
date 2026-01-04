//go:build !windows

package xdg

import (
	"errors"
	"path/filepath"
	"testing"
)

func TestConfigHomeWithXDGEnvVar(t *testing.T) {
	getenv := func(key string) string {
		if key == "XDG_CONFIG_HOME" {
			return "/custom/config"
		}
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.ConfigHome()

	if got != "/custom/config" {
		t.Errorf("ConfigHome: want /custom/config, got %q", got)
	}
}

func TestConfigHomeDefault(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.ConfigHome()

	want := filepath.Join("/home/user", ".config")
	if got != want {
		t.Errorf("ConfigHome: want %q, got %q", want, got)
	}
}

func TestConfigHomeNoHomeDir(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "", errors.New("no home directory")
	}

	p := newWithEnv(getenv, homeDir)
	got := p.ConfigHome()

	if got != "" {
		t.Errorf("ConfigHome: want empty string on error, got %q", got)
	}
}

func TestCacheHomeWithXDGEnvVar(t *testing.T) {
	getenv := func(key string) string {
		if key == "XDG_CACHE_HOME" {
			return "/custom/cache"
		}
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.CacheHome()

	if got != "/custom/cache" {
		t.Errorf("CacheHome: want /custom/cache, got %q", got)
	}
}

func TestCacheHomeDefault(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.CacheHome()

	want := filepath.Join("/home/user", ".cache")
	if got != want {
		t.Errorf("CacheHome: want %q, got %q", want, got)
	}
}

func TestDataHomeWithXDGEnvVar(t *testing.T) {
	getenv := func(key string) string {
		if key == "XDG_DATA_HOME" {
			return "/custom/data"
		}
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.DataHome()

	if got != "/custom/data" {
		t.Errorf("DataHome: want /custom/data, got %q", got)
	}
}

func TestDataHomeDefault(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.DataHome()

	want := filepath.Join("/home/user", ".local", "share")
	if got != want {
		t.Errorf("DataHome: want %q, got %q", want, got)
	}
}

func TestSystemConfigDir(t *testing.T) {
	p := New()
	got := p.SystemConfigDir()

	if got != "/etc" {
		t.Errorf("SystemConfigDir: want /etc, got %q", got)
	}
}

func TestMorphirConfigHome(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.MorphirConfigHome()

	want := filepath.Join("/home/user", ".config", "morphir")
	if got != want {
		t.Errorf("MorphirConfigHome: want %q, got %q", want, got)
	}
}

func TestMorphirCacheHome(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.MorphirCacheHome()

	want := filepath.Join("/home/user", ".cache", "morphir")
	if got != want {
		t.Errorf("MorphirCacheHome: want %q, got %q", want, got)
	}
}

func TestMorphirDataHome(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.MorphirDataHome()

	want := filepath.Join("/home/user", ".local", "share", "morphir")
	if got != want {
		t.Errorf("MorphirDataHome: want %q, got %q", want, got)
	}
}

func TestMorphirSystemConfig(t *testing.T) {
	p := New()
	got := p.MorphirSystemConfig()

	want := filepath.Join("/etc", "morphir")
	if got != want {
		t.Errorf("MorphirSystemConfig: want %q, got %q", want, got)
	}
}

func TestGlobalConfigFile(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "/home/user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.GlobalConfigFile()

	want := filepath.Join("/home/user", ".config", "morphir", "morphir.toml")
	if got != want {
		t.Errorf("GlobalConfigFile: want %q, got %q", want, got)
	}
}

func TestSystemConfigFile(t *testing.T) {
	p := New()
	got := p.SystemConfigFile()

	want := filepath.Join("/etc", "morphir", "morphir.toml")
	if got != want {
		t.Errorf("SystemConfigFile: want %q, got %q", want, got)
	}
}

func TestIsWindowsFalseOnUnix(t *testing.T) {
	p := New()
	if p.isWindows() {
		t.Error("isWindows: want false on Unix, got true")
	}
}
