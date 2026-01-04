package config

import (
	"os"
	"testing"
)

func TestDefaultReturnsExpectedDefaults(t *testing.T) {
	cfg := Default()

	// IR section defaults
	if got := cfg.IR().FormatVersion(); got != 3 {
		t.Errorf("IR.FormatVersion: want 3, got %d", got)
	}
	if got := cfg.IR().StrictMode(); got != false {
		t.Errorf("IR.StrictMode: want false, got %t", got)
	}

	// Workspace section defaults
	if got := cfg.Workspace().OutputDir(); got != ".morphir" {
		t.Errorf("Workspace.OutputDir: want .morphir, got %q", got)
	}
	if got := cfg.Workspace().Root(); got != "" {
		t.Errorf("Workspace.Root: want empty, got %q", got)
	}

	// Codegen section defaults
	if got := cfg.Codegen().OutputFormat(); got != "pretty" {
		t.Errorf("Codegen.OutputFormat: want pretty, got %q", got)
	}
	if got := cfg.Codegen().Targets(); got != nil {
		t.Errorf("Codegen.Targets: want nil, got %v", got)
	}

	// Cache section defaults
	if got := cfg.Cache().Enabled(); got != true {
		t.Errorf("Cache.Enabled: want true, got %t", got)
	}
	if got := cfg.Cache().MaxSize(); got != 0 {
		t.Errorf("Cache.MaxSize: want 0, got %d", got)
	}

	// Logging section defaults
	if got := cfg.Logging().Level(); got != "info" {
		t.Errorf("Logging.Level: want info, got %q", got)
	}
	if got := cfg.Logging().Format(); got != "text" {
		t.Errorf("Logging.Format: want text, got %q", got)
	}

	// UI section defaults
	if got := cfg.UI().Color(); got != true {
		t.Errorf("UI.Color: want true, got %t", got)
	}
	if got := cfg.UI().Interactive(); got != true {
		t.Errorf("UI.Interactive: want true, got %t", got)
	}
	if got := cfg.UI().Theme(); got != "default" {
		t.Errorf("UI.Theme: want default, got %q", got)
	}
}

func TestCodegenTargetsDefensiveCopy(t *testing.T) {
	// Create a config with targets
	cfg := Config{
		codegen: CodegenSection{
			targets: []string{"go", "scala"},
		},
	}

	// Get targets and modify the returned slice
	targets := cfg.Codegen().Targets()
	if targets == nil {
		t.Fatal("expected non-nil targets")
	}
	targets[0] = "mutated"

	// Original should be unchanged
	originalTargets := cfg.Codegen().Targets()
	if originalTargets[0] != "go" {
		t.Errorf("defensive copy failed: original was mutated to %q", originalTargets[0])
	}
}

func TestLoadResultSourcesDefensiveCopy(t *testing.T) {
	// Create a LoadResult with sources
	result := LoadResult{
		sources: []SourceInfo{
			{name: "project", path: "/path/to/morphir.toml", priority: 4},
		},
	}

	// Get sources and modify the returned slice
	sources := result.Sources()
	if sources == nil {
		t.Fatal("expected non-nil sources")
	}
	sources[0] = SourceInfo{name: "mutated"}

	// Original should be unchanged
	originalSources := result.Sources()
	if originalSources[0].Name() != "project" {
		t.Errorf("defensive copy failed: original was mutated to %q", originalSources[0].Name())
	}
}

func TestSourceInfoAccessors(t *testing.T) {
	info := SourceInfo{
		name:     "project",
		path:     "/home/user/project/morphir.toml",
		priority: 4,
	}

	if got := info.Name(); got != "project" {
		t.Errorf("Name: want project, got %q", got)
	}
	if got := info.Path(); got != "/home/user/project/morphir.toml" {
		t.Errorf("Path: want /home/user/project/morphir.toml, got %q", got)
	}
	if got := info.Priority(); got != 4 {
		t.Errorf("Priority: want 4, got %d", got)
	}
}

func TestLoadReturnsDefaults(t *testing.T) {
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}

	// Should return defaults when no config files exist
	if got := cfg.IR().FormatVersion(); got != 3 {
		t.Errorf("IR.FormatVersion: want 3, got %d", got)
	}
}

func TestLoadWithDetailsReturnsConfig(t *testing.T) {
	result, err := LoadWithDetails()
	if err != nil {
		t.Fatalf("LoadWithDetails: unexpected error: %v", err)
	}

	cfg := result.Config()
	if got := cfg.IR().FormatVersion(); got != 3 {
		t.Errorf("IR.FormatVersion: want 3, got %d", got)
	}
}

func TestLoadWithDetailsReturnsSources(t *testing.T) {
	result, err := LoadWithDetails()
	if err != nil {
		t.Fatalf("LoadWithDetails: unexpected error: %v", err)
	}

	sources := result.Sources()
	// At minimum, defaults should always be loaded
	if len(sources) == 0 {
		t.Error("expected at least one source (defaults)")
	}

	// Check that defaults source is present
	foundDefaults := false
	for _, src := range sources {
		if src.Name() == "defaults" {
			foundDefaults = true
			if src.Priority() != 0 {
				t.Errorf("defaults priority: want 0, got %d", src.Priority())
			}
			break
		}
	}
	if !foundDefaults {
		t.Error("expected defaults source to be present")
	}
}

func TestLoadWithWorkDir(t *testing.T) {
	// Create a temp directory with a config file
	tmpDir := t.TempDir()
	configPath := tmpDir + "/morphir.toml"
	configContent := `
[ir]
format_version = 5
strict_mode = true

[logging]
level = "debug"
`
	if err := writeFile(configPath, configContent); err != nil {
		t.Fatalf("failed to write config file: %v", err)
	}

	// Load with the temp directory
	cfg, err := Load(
		WithWorkDir(tmpDir),
		WithoutSystem(),
		WithoutGlobal(),
		WithoutEnv(),
	)
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}

	// Verify project config values are loaded
	if got := cfg.IR().FormatVersion(); got != 5 {
		t.Errorf("IR.FormatVersion: want 5, got %d", got)
	}
	if got := cfg.IR().StrictMode(); got != true {
		t.Errorf("IR.StrictMode: want true, got %t", got)
	}
	if got := cfg.Logging().Level(); got != "debug" {
		t.Errorf("Logging.Level: want debug, got %q", got)
	}
}

func TestLoadWithEnvOverride(t *testing.T) {
	// Set environment variable
	t.Setenv("MORPHIR_LOGGING__LEVEL", "error")

	cfg, err := Load(
		WithoutSystem(),
		WithoutGlobal(),
		WithoutProject(),
		WithoutUser(),
	)
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}

	// Env should override defaults
	if got := cfg.Logging().Level(); got != "error" {
		t.Errorf("Logging.Level: want error, got %q", got)
	}
}

func TestLoadWithCustomEnvPrefix(t *testing.T) {
	// Set environment variable with custom prefix
	t.Setenv("MYAPP_LOGGING__LEVEL", "warn")

	cfg, err := Load(
		WithEnvPrefix("MYAPP"),
		WithoutSystem(),
		WithoutGlobal(),
		WithoutProject(),
		WithoutUser(),
	)
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}

	// Custom prefix env should override defaults
	if got := cfg.Logging().Level(); got != "warn" {
		t.Errorf("Logging.Level: want warn, got %q", got)
	}
}

func TestLoadPriorityOrder(t *testing.T) {
	// Create temp directory with project and user configs
	tmpDir := t.TempDir()

	// Project config sets level to "info"
	projectConfig := tmpDir + "/morphir.toml"
	if err := writeFile(projectConfig, `[logging]
level = "info"
`); err != nil {
		t.Fatalf("failed to write project config: %v", err)
	}

	// User override sets level to "debug"
	userDir := tmpDir + "/.morphir"
	if err := mkdir(userDir); err != nil {
		t.Fatalf("failed to create .morphir dir: %v", err)
	}
	userConfig := userDir + "/morphir.user.toml"
	if err := writeFile(userConfig, `[logging]
level = "debug"
`); err != nil {
		t.Fatalf("failed to write user config: %v", err)
	}

	cfg, err := Load(
		WithWorkDir(tmpDir),
		WithoutSystem(),
		WithoutGlobal(),
		WithoutEnv(),
	)
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}

	// User override should take precedence over project
	if got := cfg.Logging().Level(); got != "debug" {
		t.Errorf("Logging.Level: want debug (from user override), got %q", got)
	}
}

func TestFromMapNil(t *testing.T) {
	cfg := FromMap(nil)
	// Should return defaults
	if got := cfg.IR().FormatVersion(); got != 3 {
		t.Errorf("IR.FormatVersion: want 3, got %d", got)
	}
}

func TestFromMapPartial(t *testing.T) {
	m := map[string]any{
		"ir": map[string]any{
			"format_version": int64(4),
		},
	}
	cfg := FromMap(m)

	// Specified value should be set
	if got := cfg.IR().FormatVersion(); got != 4 {
		t.Errorf("IR.FormatVersion: want 4, got %d", got)
	}

	// Other values should be defaults
	if got := cfg.Logging().Level(); got != "info" {
		t.Errorf("Logging.Level: want info (default), got %q", got)
	}
}

func TestFromMapComplete(t *testing.T) {
	m := completeTestMap()
	cfg := FromMap(m)

	t.Run("morphir section", func(t *testing.T) {
		assertString(t, "Morphir.Version", "1.0.0", cfg.Morphir().Version())
	})

	t.Run("workspace section", func(t *testing.T) {
		assertString(t, "Workspace.Root", "/my/project", cfg.Workspace().Root())
		assertString(t, "Workspace.OutputDir", "build", cfg.Workspace().OutputDir())
	})

	t.Run("ir section", func(t *testing.T) {
		assertInt(t, "IR.FormatVersion", 4, cfg.IR().FormatVersion())
		assertBool(t, "IR.StrictMode", true, cfg.IR().StrictMode())
	})

	t.Run("codegen section", func(t *testing.T) {
		targets := cfg.Codegen().Targets()
		if len(targets) != 2 || targets[0] != "go" {
			t.Errorf("Codegen.Targets: want [go scala], got %v", targets)
		}
		assertString(t, "Codegen.TemplateDir", "/templates", cfg.Codegen().TemplateDir())
		assertString(t, "Codegen.OutputFormat", "compact", cfg.Codegen().OutputFormat())
	})

	t.Run("cache section", func(t *testing.T) {
		assertBool(t, "Cache.Enabled", false, cfg.Cache().Enabled())
		assertString(t, "Cache.Dir", "/cache", cfg.Cache().Dir())
		assertInt64(t, "Cache.MaxSize", 1024, cfg.Cache().MaxSize())
	})

	t.Run("logging section", func(t *testing.T) {
		assertString(t, "Logging.Level", "debug", cfg.Logging().Level())
		assertString(t, "Logging.Format", "json", cfg.Logging().Format())
		assertString(t, "Logging.File", "/var/log/morphir.log", cfg.Logging().File())
	})

	t.Run("ui section", func(t *testing.T) {
		assertBool(t, "UI.Color", false, cfg.UI().Color())
		assertBool(t, "UI.Interactive", false, cfg.UI().Interactive())
		assertString(t, "UI.Theme", "dark", cfg.UI().Theme())
	})
}

func completeTestMap() map[string]any {
	return map[string]any{
		"morphir": map[string]any{
			"version": "1.0.0",
		},
		"workspace": map[string]any{
			"root":       "/my/project",
			"output_dir": "build",
		},
		"ir": map[string]any{
			"format_version": int64(4),
			"strict_mode":    true,
		},
		"codegen": map[string]any{
			"targets":       []string{"go", "scala"},
			"template_dir":  "/templates",
			"output_format": "compact",
		},
		"cache": map[string]any{
			"enabled":  false,
			"dir":      "/cache",
			"max_size": int64(1024),
		},
		"logging": map[string]any{
			"level":  "debug",
			"format": "json",
			"file":   "/var/log/morphir.log",
		},
		"ui": map[string]any{
			"color":       false,
			"interactive": false,
			"theme":       "dark",
		},
	}
}

func assertString(t *testing.T, name, want, got string) {
	t.Helper()
	if got != want {
		t.Errorf("%s: want %q, got %q", name, want, got)
	}
}

func assertInt(t *testing.T, name string, want, got int) {
	t.Helper()
	if got != want {
		t.Errorf("%s: want %d, got %d", name, want, got)
	}
}

func assertInt64(t *testing.T, name string, want, got int64) {
	t.Helper()
	if got != want {
		t.Errorf("%s: want %d, got %d", name, want, got)
	}
}

func assertBool(t *testing.T, name string, want, got bool) {
	t.Helper()
	if got != want {
		t.Errorf("%s: want %t, got %t", name, want, got)
	}
}

func TestNewSourceInfo(t *testing.T) {
	info := NewSourceInfo("project", "/path/to/morphir.toml", 300, true, nil)

	if got := info.Name(); got != "project" {
		t.Errorf("Name: want project, got %q", got)
	}
	if got := info.Path(); got != "/path/to/morphir.toml" {
		t.Errorf("Path: want /path/to/morphir.toml, got %q", got)
	}
	if got := info.Priority(); got != 300 {
		t.Errorf("Priority: want 300, got %d", got)
	}
	if got := info.Loaded(); got != true {
		t.Errorf("Loaded: want true, got %v", got)
	}
	if got := info.Error(); got != nil {
		t.Errorf("Error: want nil, got %v", got)
	}
}

func TestNewLoadResult(t *testing.T) {
	cfg := Default()
	sources := []SourceInfo{
		NewSourceInfo("defaults", "(built-in)", 0, true, nil),
		NewSourceInfo("project", "/path/morphir.toml", 300, true, nil),
	}
	result := NewLoadResult(cfg, sources)

	if got := result.Config().IR().FormatVersion(); got != 3 {
		t.Errorf("Config.IR.FormatVersion: want 3, got %d", got)
	}
	if got := len(result.Sources()); got != 2 {
		t.Errorf("Sources length: want 2, got %d", got)
	}
}

// Helper functions for tests
func writeFile(path, content string) error {
	return os.WriteFile(path, []byte(content), 0644)
}

func mkdir(path string) error {
	return os.MkdirAll(path, 0755)
}
