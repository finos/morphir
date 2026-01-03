package config

import (
	"testing"
)

func TestDefaultLoadOptions(t *testing.T) {
	opts := defaultLoadOptions()

	if opts.workDir != "" {
		t.Errorf("workDir: want empty, got %q", opts.workDir)
	}
	if opts.skipSystem {
		t.Error("skipSystem: want false, got true")
	}
	if opts.skipGlobal {
		t.Error("skipGlobal: want false, got true")
	}
	if opts.skipProject {
		t.Error("skipProject: want false, got true")
	}
	if opts.skipUser {
		t.Error("skipUser: want false, got true")
	}
	if opts.skipEnv {
		t.Error("skipEnv: want false, got true")
	}
	if opts.configPath != "" {
		t.Errorf("configPath: want empty, got %q", opts.configPath)
	}
	if opts.envPrefix != "MORPHIR" {
		t.Errorf("envPrefix: want MORPHIR, got %q", opts.envPrefix)
	}
}

func TestWithWorkDir(t *testing.T) {
	opts := defaultLoadOptions()
	WithWorkDir("/custom/path")(&opts)

	if opts.workDir != "/custom/path" {
		t.Errorf("workDir: want /custom/path, got %q", opts.workDir)
	}
}

func TestWithConfigPath(t *testing.T) {
	opts := defaultLoadOptions()
	WithConfigPath("/explicit/config.toml")(&opts)

	if opts.configPath != "/explicit/config.toml" {
		t.Errorf("configPath: want /explicit/config.toml, got %q", opts.configPath)
	}
}

func TestWithEnvPrefix(t *testing.T) {
	opts := defaultLoadOptions()
	WithEnvPrefix("MYAPP")(&opts)

	if opts.envPrefix != "MYAPP" {
		t.Errorf("envPrefix: want MYAPP, got %q", opts.envPrefix)
	}
}

func TestWithoutSystem(t *testing.T) {
	opts := defaultLoadOptions()
	WithoutSystem()(&opts)

	if !opts.skipSystem {
		t.Error("skipSystem: want true, got false")
	}
}

func TestWithoutGlobal(t *testing.T) {
	opts := defaultLoadOptions()
	WithoutGlobal()(&opts)

	if !opts.skipGlobal {
		t.Error("skipGlobal: want true, got false")
	}
}

func TestWithoutProject(t *testing.T) {
	opts := defaultLoadOptions()
	WithoutProject()(&opts)

	if !opts.skipProject {
		t.Error("skipProject: want true, got false")
	}
}

func TestWithoutUser(t *testing.T) {
	opts := defaultLoadOptions()
	WithoutUser()(&opts)

	if !opts.skipUser {
		t.Error("skipUser: want true, got false")
	}
}

func TestWithoutEnv(t *testing.T) {
	opts := defaultLoadOptions()
	WithoutEnv()(&opts)

	if !opts.skipEnv {
		t.Error("skipEnv: want true, got false")
	}
}

func TestMultipleOptions(t *testing.T) {
	opts := defaultLoadOptions()

	// Apply multiple options
	WithWorkDir("/project")(&opts)
	WithEnvPrefix("CUSTOM")(&opts)
	WithoutSystem()(&opts)
	WithoutGlobal()(&opts)

	if opts.workDir != "/project" {
		t.Errorf("workDir: want /project, got %q", opts.workDir)
	}
	if opts.envPrefix != "CUSTOM" {
		t.Errorf("envPrefix: want CUSTOM, got %q", opts.envPrefix)
	}
	if !opts.skipSystem {
		t.Error("skipSystem: want true, got false")
	}
	if !opts.skipGlobal {
		t.Error("skipGlobal: want true, got false")
	}
	// These should still be defaults
	if opts.skipProject {
		t.Error("skipProject: want false, got true")
	}
	if opts.skipUser {
		t.Error("skipUser: want false, got true")
	}
}

func TestLoadWithOptions(t *testing.T) {
	// Test that Load accepts options without error
	cfg, err := Load(
		WithWorkDir("/test"),
		WithoutEnv(),
	)
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}

	// Should still return defaults
	if got := cfg.IR().FormatVersion(); got != 3 {
		t.Errorf("IR.FormatVersion: want 3, got %d", got)
	}
}

func TestLoadWithDetailsWithOptions(t *testing.T) {
	// Test that LoadWithDetails accepts options without error
	result, err := LoadWithDetails(
		WithConfigPath("/explicit/path.toml"),
	)
	if err != nil {
		t.Fatalf("LoadWithDetails: unexpected error: %v", err)
	}

	cfg := result.Config()
	if got := cfg.IR().FormatVersion(); got != 3 {
		t.Errorf("IR.FormatVersion: want 3, got %d", got)
	}
}
