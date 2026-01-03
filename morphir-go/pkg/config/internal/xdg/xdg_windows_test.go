//go:build windows

package xdg

import (
	"errors"
	"testing"
)

func TestConfigHomeWithAppDataEnvVar(t *testing.T) {
	getenv := func(key string) string {
		if key == "APPDATA" {
			return "C:\\Users\\user\\AppData\\Roaming"
		}
		return ""
	}
	homeDir := func() (string, error) {
		return "C:\\Users\\user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.ConfigHome()

	if got != "C:\\Users\\user\\AppData\\Roaming" {
		t.Errorf("ConfigHome: want C:\\Users\\user\\AppData\\Roaming, got %q", got)
	}
}

func TestConfigHomeFallback(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "C:\\Users\\user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.ConfigHome()

	want := "C:\\Users\\user\\AppData\\Roaming"
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

func TestCacheHomeWithLocalAppDataEnvVar(t *testing.T) {
	getenv := func(key string) string {
		if key == "LOCALAPPDATA" {
			return "C:\\Users\\user\\AppData\\Local"
		}
		return ""
	}
	homeDir := func() (string, error) {
		return "C:\\Users\\user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.CacheHome()

	if got != "C:\\Users\\user\\AppData\\Local" {
		t.Errorf("CacheHome: want C:\\Users\\user\\AppData\\Local, got %q", got)
	}
}

func TestCacheHomeFallback(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "C:\\Users\\user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.CacheHome()

	want := "C:\\Users\\user\\AppData\\Local"
	if got != want {
		t.Errorf("CacheHome: want %q, got %q", want, got)
	}
}

func TestDataHomeWithLocalAppDataEnvVar(t *testing.T) {
	getenv := func(key string) string {
		if key == "LOCALAPPDATA" {
			return "C:\\Users\\user\\AppData\\Local"
		}
		return ""
	}
	homeDir := func() (string, error) {
		return "C:\\Users\\user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.DataHome()

	if got != "C:\\Users\\user\\AppData\\Local" {
		t.Errorf("DataHome: want C:\\Users\\user\\AppData\\Local, got %q", got)
	}
}

func TestSystemConfigDirWithProgramDataEnvVar(t *testing.T) {
	getenv := func(key string) string {
		if key == "PROGRAMDATA" {
			return "C:\\ProgramData"
		}
		return ""
	}
	homeDir := func() (string, error) {
		return "C:\\Users\\user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.SystemConfigDir()

	if got != "C:\\ProgramData" {
		t.Errorf("SystemConfigDir: want C:\\ProgramData, got %q", got)
	}
}

func TestSystemConfigDirFallback(t *testing.T) {
	getenv := func(key string) string {
		return ""
	}
	homeDir := func() (string, error) {
		return "C:\\Users\\user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.SystemConfigDir()

	if got != "C:\\ProgramData" {
		t.Errorf("SystemConfigDir: want C:\\ProgramData, got %q", got)
	}
}

func TestMorphirConfigHome(t *testing.T) {
	getenv := func(key string) string {
		if key == "APPDATA" {
			return "C:\\Users\\user\\AppData\\Roaming"
		}
		return ""
	}
	homeDir := func() (string, error) {
		return "C:\\Users\\user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.MorphirConfigHome()

	want := "C:\\Users\\user\\AppData\\Roaming\\morphir"
	if got != want {
		t.Errorf("MorphirConfigHome: want %q, got %q", want, got)
	}
}

func TestMorphirCacheHomeOnWindows(t *testing.T) {
	getenv := func(key string) string {
		if key == "LOCALAPPDATA" {
			return "C:\\Users\\user\\AppData\\Local"
		}
		return ""
	}
	homeDir := func() (string, error) {
		return "C:\\Users\\user", nil
	}

	p := newWithEnv(getenv, homeDir)
	got := p.MorphirCacheHome()

	// On Windows, cache is under morphir/cache subdirectory
	want := "C:\\Users\\user\\AppData\\Local\\morphir\\cache"
	if got != want {
		t.Errorf("MorphirCacheHome: want %q, got %q", want, got)
	}
}

func TestIsWindowsTrueOnWindows(t *testing.T) {
	p := New()
	if !p.isWindows() {
		t.Error("isWindows: want true on Windows, got false")
	}
}
