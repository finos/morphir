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

// TaskSection Tests

func TestDefaultTasksEmpty(t *testing.T) {
	cfg := Default()

	tasks := cfg.Tasks()
	if got := tasks.Len(); got != 0 {
		t.Errorf("Tasks.Len: want 0, got %d", got)
	}
	if got := tasks.Names(); got != nil {
		t.Errorf("Tasks.Names: want nil, got %v", got)
	}
}

func TestTasksSectionGet(t *testing.T) {
	tasks := TasksSection{
		definitions: map[string]Task{
			"build": IntrinsicTask{
				taskCommon: taskCommon{
					dependsOn: []string{"setup"},
				},
				action: "morphir.pipeline.compile",
			},
		},
	}

	t.Run("existing task", func(t *testing.T) {
		task, ok := tasks.Get("build")
		if !ok {
			t.Fatal("expected task 'build' to exist")
		}
		intrinsic, ok := task.(IntrinsicTask)
		if !ok {
			t.Fatal("expected IntrinsicTask type")
		}
		if intrinsic.Action() != "morphir.pipeline.compile" {
			t.Errorf("task.Action: want morphir.pipeline.compile, got %q", intrinsic.Action())
		}
	})

	t.Run("non-existing task", func(t *testing.T) {
		_, ok := tasks.Get("nonexistent")
		if ok {
			t.Error("expected task 'nonexistent' to not exist")
		}
	})

	t.Run("nil definitions", func(t *testing.T) {
		emptyTasks := TasksSection{definitions: nil}
		_, ok := emptyTasks.Get("build")
		if ok {
			t.Error("expected no tasks in empty section")
		}
	})
}

func TestTasksSectionNames(t *testing.T) {
	tasks := TasksSection{
		definitions: map[string]Task{
			"build": IntrinsicTask{},
			"test":  IntrinsicTask{},
			"clean": IntrinsicTask{},
		},
	}

	names := tasks.Names()
	if len(names) != 3 {
		t.Fatalf("expected 3 names, got %d", len(names))
	}

	// Names should be present (order may vary due to map iteration)
	nameSet := make(map[string]bool)
	for _, name := range names {
		nameSet[name] = true
	}
	for _, expected := range []string{"build", "test", "clean"} {
		if !nameSet[expected] {
			t.Errorf("expected name %q to be present", expected)
		}
	}
}

func TestTasksSectionLen(t *testing.T) {
	t.Run("with tasks", func(t *testing.T) {
		tasks := TasksSection{
			definitions: map[string]Task{
				"build": IntrinsicTask{},
				"test":  IntrinsicTask{},
			},
		}
		if got := tasks.Len(); got != 2 {
			t.Errorf("Len: want 2, got %d", got)
		}
	})

	t.Run("nil definitions", func(t *testing.T) {
		tasks := TasksSection{definitions: nil}
		if got := tasks.Len(); got != 0 {
			t.Errorf("Len: want 0, got %d", got)
		}
	})
}

func TestCommandTaskAccessors(t *testing.T) {
	task := CommandTask{
		taskCommon: taskCommon{
			dependsOn: []string{"compile"},
			pre:       []string{"setup"},
			post:      []string{"cleanup"},
			inputs:    []string{"workspace:/src/**/*.go"},
			outputs:   []string{"workspace:/build/**"},
			params:    map[string]any{"profile": "dev", "verbose": true},
			env:       map[string]string{"GOFLAGS": "-mod=mod"},
			mounts:    map[string]string{"workspace": "rw", "config": "ro"},
		},
		cmd: []string{"go", "test", "./..."},
	}

	// Test Cmd
	cmd := task.Cmd()
	if len(cmd) != 3 || cmd[0] != "go" || cmd[1] != "test" || cmd[2] != "./..." {
		t.Errorf("Cmd: want [go test ./...], got %v", cmd)
	}

	// Test DependsOn
	deps := task.DependsOn()
	if len(deps) != 1 || deps[0] != "compile" {
		t.Errorf("DependsOn: want [compile], got %v", deps)
	}

	// Test Pre
	pre := task.Pre()
	if len(pre) != 1 || pre[0] != "setup" {
		t.Errorf("Pre: want [setup], got %v", pre)
	}

	// Test Post
	post := task.Post()
	if len(post) != 1 || post[0] != "cleanup" {
		t.Errorf("Post: want [cleanup], got %v", post)
	}

	// Test Inputs
	inputs := task.Inputs()
	if len(inputs) != 1 || inputs[0] != "workspace:/src/**/*.go" {
		t.Errorf("Inputs: want [workspace:/src/**/*.go], got %v", inputs)
	}

	// Test Outputs
	outputs := task.Outputs()
	if len(outputs) != 1 || outputs[0] != "workspace:/build/**" {
		t.Errorf("Outputs: want [workspace:/build/**], got %v", outputs)
	}

	// Test Params
	params := task.Params()
	if params["profile"] != "dev" || params["verbose"] != true {
		t.Errorf("Params: want {profile:dev, verbose:true}, got %v", params)
	}

	// Test Env
	env := task.Env()
	if env["GOFLAGS"] != "-mod=mod" {
		t.Errorf("Env: want {GOFLAGS:-mod=mod}, got %v", env)
	}

	// Test Mounts
	mounts := task.Mounts()
	if mounts["workspace"] != "rw" || mounts["config"] != "ro" {
		t.Errorf("Mounts: want {workspace:rw, config:ro}, got %v", mounts)
	}
}

func TestIntrinsicTaskAccessors(t *testing.T) {
	task := IntrinsicTask{
		taskCommon: taskCommon{
			dependsOn: []string{"setup"},
		},
		action: "morphir.pipeline.compile",
	}

	assertString(t, "Action", "morphir.pipeline.compile", task.Action())

	deps := task.DependsOn()
	if len(deps) != 1 || deps[0] != "setup" {
		t.Errorf("DependsOn: want [setup], got %v", deps)
	}
}

func TestEmptyTaskAccessors(t *testing.T) {
	t.Run("empty intrinsic task", func(t *testing.T) {
		task := IntrinsicTask{}
		if task.Action() != "" {
			t.Errorf("Action: want empty, got %q", task.Action())
		}
		if task.DependsOn() != nil {
			t.Errorf("DependsOn: want nil, got %v", task.DependsOn())
		}
		if task.Pre() != nil {
			t.Errorf("Pre: want nil, got %v", task.Pre())
		}
		if task.Post() != nil {
			t.Errorf("Post: want nil, got %v", task.Post())
		}
		if task.Inputs() != nil {
			t.Errorf("Inputs: want nil, got %v", task.Inputs())
		}
		if task.Outputs() != nil {
			t.Errorf("Outputs: want nil, got %v", task.Outputs())
		}
		if task.Params() != nil {
			t.Errorf("Params: want nil, got %v", task.Params())
		}
		if task.Env() != nil {
			t.Errorf("Env: want nil, got %v", task.Env())
		}
		if task.Mounts() != nil {
			t.Errorf("Mounts: want nil, got %v", task.Mounts())
		}
	})

	t.Run("empty command task", func(t *testing.T) {
		task := CommandTask{}
		if task.Cmd() != nil {
			t.Errorf("Cmd: want nil, got %v", task.Cmd())
		}
		if task.DependsOn() != nil {
			t.Errorf("DependsOn: want nil, got %v", task.DependsOn())
		}
	})
}

func TestTaskDefensiveCopy(t *testing.T) {
	task := CommandTask{
		taskCommon: taskCommon{
			dependsOn: []string{"setup"},
			pre:       []string{"lint"},
			post:      []string{"test"},
			inputs:    []string{"*.go"},
			outputs:   []string{"./bin/*"},
			params:    map[string]any{"opt": "value"},
			env:       map[string]string{"KEY": "value"},
			mounts:    map[string]string{"src": "ro"},
		},
		cmd: []string{"go", "build"},
	}

	// Modify returned slices
	task.Cmd()[0] = "mutated"
	task.DependsOn()[0] = "mutated"
	task.Pre()[0] = "mutated"
	task.Post()[0] = "mutated"
	task.Inputs()[0] = "mutated"
	task.Outputs()[0] = "mutated"

	// Modify returned maps
	task.Params()["opt"] = "mutated"
	task.Env()["KEY"] = "mutated"
	task.Mounts()["src"] = "mutated"

	// Verify originals are unchanged
	if task.Cmd()[0] != "go" {
		t.Error("Cmd defensive copy failed")
	}
	if task.DependsOn()[0] != "setup" {
		t.Error("DependsOn defensive copy failed")
	}
	if task.Pre()[0] != "lint" {
		t.Error("Pre defensive copy failed")
	}
	if task.Post()[0] != "test" {
		t.Error("Post defensive copy failed")
	}
	if task.Inputs()[0] != "*.go" {
		t.Error("Inputs defensive copy failed")
	}
	if task.Outputs()[0] != "./bin/*" {
		t.Error("Outputs defensive copy failed")
	}
	if task.Params()["opt"] != "value" {
		t.Error("Params defensive copy failed")
	}
	if task.Env()["KEY"] != "value" {
		t.Error("Env defensive copy failed")
	}
	if task.Mounts()["src"] != "ro" {
		t.Error("Mounts defensive copy failed")
	}
}

func TestFromMapWithTasks(t *testing.T) {
	m := map[string]any{
		"tasks": map[string]any{
			"build": map[string]any{
				"kind":       "intrinsic",
				"action":     "morphir.pipeline.compile",
				"depends_on": []any{"setup"},
				"inputs":     []any{"workspace:/src/**"},
				"outputs":    []any{"workspace:/build/**"},
			},
			"codegen": map[string]any{
				"kind": "command",
				"cmd":  []any{"morphir", "gen", "--target", "Scala"},
				"env": map[string]any{
					"GOFLAGS": "-mod=mod",
				},
				"mounts": map[string]any{
					"workspace": "rw",
					"config":    "ro",
				},
			},
		},
	}

	cfg := FromMap(m)
	tasks := cfg.Tasks()

	if tasks.Len() != 2 {
		t.Fatalf("expected 2 tasks, got %d", tasks.Len())
	}

	// Test build task (intrinsic)
	build, ok := tasks.Get("build")
	if !ok {
		t.Fatal("expected 'build' task to exist")
	}
	buildIntrinsic, ok := build.(IntrinsicTask)
	if !ok {
		t.Fatalf("build: want IntrinsicTask, got %T", build)
	}
	if buildIntrinsic.Action() != "morphir.pipeline.compile" {
		t.Errorf("build.Action: want morphir.pipeline.compile, got %q", buildIntrinsic.Action())
	}
	if deps := build.DependsOn(); len(deps) != 1 || deps[0] != "setup" {
		t.Errorf("build.DependsOn: want [setup], got %v", deps)
	}

	// Test codegen task (command)
	codegen, ok := tasks.Get("codegen")
	if !ok {
		t.Fatal("expected 'codegen' task to exist")
	}
	codegenCmd, ok := codegen.(CommandTask)
	if !ok {
		t.Fatalf("codegen: want CommandTask, got %T", codegen)
	}
	cmd := codegenCmd.Cmd()
	if len(cmd) != 4 || cmd[0] != "morphir" {
		t.Errorf("codegen.Cmd: want [morphir gen --target Scala], got %v", cmd)
	}
	if env := codegen.Env(); env["GOFLAGS"] != "-mod=mod" {
		t.Errorf("codegen.Env: want GOFLAGS=-mod=mod, got %v", env)
	}
	if mounts := codegen.Mounts(); mounts["workspace"] != "rw" {
		t.Errorf("codegen.Mounts: want workspace=rw, got %v", mounts)
	}
}

func TestFromMapTasksWithParams(t *testing.T) {
	m := map[string]any{
		"tasks": map[string]any{
			"compile": map[string]any{
				"kind":   "intrinsic",
				"action": "morphir.pipeline.compile",
				"params": map[string]any{
					"profile":    "production",
					"optimize":   true,
					"max_errors": int64(10),
				},
			},
		},
	}

	cfg := FromMap(m)
	compile, ok := cfg.Tasks().Get("compile")
	if !ok {
		t.Fatal("expected 'compile' task to exist")
	}

	params := compile.Params()
	if params["profile"] != "production" {
		t.Errorf("params.profile: want production, got %v", params["profile"])
	}
	if params["optimize"] != true {
		t.Errorf("params.optimize: want true, got %v", params["optimize"])
	}
	if params["max_errors"] != int64(10) {
		t.Errorf("params.max_errors: want 10, got %v", params["max_errors"])
	}
}

func TestFromMapTasksWithPrePost(t *testing.T) {
	m := map[string]any{
		"tasks": map[string]any{
			"build": map[string]any{
				"kind": "intrinsic",
				"pre":  []any{"lint", "format"},
				"post": []any{"test", "deploy"},
			},
		},
	}

	cfg := FromMap(m)
	build, ok := cfg.Tasks().Get("build")
	if !ok {
		t.Fatal("expected 'build' task to exist")
	}

	pre := build.Pre()
	if len(pre) != 2 || pre[0] != "lint" || pre[1] != "format" {
		t.Errorf("pre: want [lint format], got %v", pre)
	}

	post := build.Post()
	if len(post) != 2 || post[0] != "test" || post[1] != "deploy" {
		t.Errorf("post: want [test deploy], got %v", post)
	}
}

func TestFromMapEmptyTasks(t *testing.T) {
	m := map[string]any{
		"tasks": map[string]any{},
	}

	cfg := FromMap(m)
	if cfg.Tasks().Len() != 0 {
		t.Errorf("expected 0 tasks for empty tasks section, got %d", cfg.Tasks().Len())
	}
}

// Bindings Section Tests

func TestDefaultBindingsEmpty(t *testing.T) {
	cfg := Default()

	bindings := cfg.Bindings()
	if !bindings.IsEmpty() {
		t.Error("expected default bindings to be empty")
	}
	if !bindings.WIT().IsEmpty() {
		t.Error("expected default WIT bindings to be empty")
	}
	if !bindings.Protobuf().IsEmpty() {
		t.Error("expected default Protobuf bindings to be empty")
	}
	if !bindings.JSON().IsEmpty() {
		t.Error("expected default JSON bindings to be empty")
	}
}

func TestFromMapWithBindings(t *testing.T) {
	m := map[string]any{
		"bindings": map[string]any{
			"wit": map[string]any{
				"primitives": []any{
					map[string]any{
						"external":      "u128",
						"morphir":       "Morphir.SDK:Int:Int128",
						"bidirectional": true,
						"priority":      int64(100),
					},
				},
				"containers": []any{
					map[string]any{
						"external_pattern": "hashmap",
						"morphir_pattern":  "Morphir.SDK:Dict:Dict",
						"type_params":      int64(2),
						"bidirectional":    true,
						"priority":         int64(100),
					},
				},
			},
		},
	}

	cfg := FromMap(m)
	bindings := cfg.Bindings()

	if bindings.IsEmpty() {
		t.Error("expected bindings to not be empty")
	}

	wit := bindings.WIT()
	if wit.IsEmpty() {
		t.Error("expected WIT bindings to not be empty")
	}
	if len(wit.Primitives) != 1 {
		t.Errorf("expected 1 primitive, got %d", len(wit.Primitives))
	}
	if wit.Primitives[0].ExternalType != "u128" {
		t.Errorf("expected external=u128, got %s", wit.Primitives[0].ExternalType)
	}
	if wit.Primitives[0].MorphirType != "Morphir.SDK:Int:Int128" {
		t.Errorf("expected morphir=Morphir.SDK:Int:Int128, got %s", wit.Primitives[0].MorphirType)
	}
	if wit.Primitives[0].Priority != 100 {
		t.Errorf("expected priority=100, got %d", wit.Primitives[0].Priority)
	}

	if len(wit.Containers) != 1 {
		t.Errorf("expected 1 container, got %d", len(wit.Containers))
	}
	if wit.Containers[0].ExternalPattern != "hashmap" {
		t.Errorf("expected external_pattern=hashmap, got %s", wit.Containers[0].ExternalPattern)
	}
	if wit.Containers[0].TypeParamCount != 2 {
		t.Errorf("expected type_params=2, got %d", wit.Containers[0].TypeParamCount)
	}
}

func TestFromMapBindingsEmptySection(t *testing.T) {
	m := map[string]any{
		"bindings": map[string]any{},
	}

	cfg := FromMap(m)
	if !cfg.Bindings().IsEmpty() {
		t.Error("expected bindings to be empty for empty bindings section")
	}
}

func TestFromMapBindingsMultipleBindingTypes(t *testing.T) {
	m := map[string]any{
		"bindings": map[string]any{
			"wit": map[string]any{
				"primitives": []any{
					map[string]any{
						"external": "u128",
						"morphir":  "Int128",
					},
				},
			},
			"protobuf": map[string]any{
				"primitives": []any{
					map[string]any{
						"external": "int32",
						"morphir":  "Int",
					},
				},
			},
			"json": map[string]any{
				"primitives": []any{
					map[string]any{
						"external": "number",
						"morphir":  "Float",
					},
				},
			},
		},
	}

	cfg := FromMap(m)
	bindings := cfg.Bindings()

	if bindings.IsEmpty() {
		t.Error("expected bindings to not be empty")
	}

	if len(bindings.WIT().Primitives) != 1 {
		t.Errorf("expected 1 WIT primitive, got %d", len(bindings.WIT().Primitives))
	}
	if len(bindings.Protobuf().Primitives) != 1 {
		t.Errorf("expected 1 Protobuf primitive, got %d", len(bindings.Protobuf().Primitives))
	}
	if len(bindings.JSON().Primitives) != 1 {
		t.Errorf("expected 1 JSON primitive, got %d", len(bindings.JSON().Primitives))
	}
}

func TestFromMapNoTasks(t *testing.T) {
	m := map[string]any{
		"ir": map[string]any{
			"format_version": int64(3),
		},
	}

	cfg := FromMap(m)
	if cfg.Tasks().Len() != 0 {
		t.Errorf("expected 0 tasks when no tasks section, got %d", cfg.Tasks().Len())
	}
}

func TestLoadWithTasksFromFile(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := tmpDir + "/morphir.toml"
	configContent := `
[tasks.compile]
kind = "intrinsic"
action = "morphir.pipeline.compile"
depends_on = ["setup"]
inputs = ["workspace:/src/**/*.elm"]
outputs = ["workspace:/build/**"]

[tasks.compile.params]
profile = "dev"

[tasks.compile.env]
GOFLAGS = "-mod=mod"

[tasks.compile.mounts]
workspace = "rw"
config = "ro"

[tasks.codegen]
kind = "command"
cmd = ["morphir", "gen", "--target", "Scala"]
pre = ["compile"]
post = ["test"]
`
	if err := writeFile(configPath, configContent); err != nil {
		t.Fatalf("failed to write config file: %v", err)
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

	tasks := cfg.Tasks()
	if tasks.Len() != 2 {
		t.Fatalf("expected 2 tasks, got %d", tasks.Len())
	}

	// Verify compile task (intrinsic)
	compile, ok := tasks.Get("compile")
	if !ok {
		t.Fatal("expected 'compile' task to exist")
	}
	compileIntrinsic, ok := compile.(IntrinsicTask)
	if !ok {
		t.Fatalf("compile: want IntrinsicTask, got %T", compile)
	}
	if compileIntrinsic.Action() != "morphir.pipeline.compile" {
		t.Errorf("compile.Action: want morphir.pipeline.compile, got %q", compileIntrinsic.Action())
	}
	if params := compile.Params(); params["profile"] != "dev" {
		t.Errorf("compile.Params: want profile=dev, got %v", params)
	}
	if env := compile.Env(); env["GOFLAGS"] != "-mod=mod" {
		t.Errorf("compile.Env: want GOFLAGS=-mod=mod, got %v", env)
	}
	if mounts := compile.Mounts(); mounts["workspace"] != "rw" {
		t.Errorf("compile.Mounts: want workspace=rw, got %v", mounts)
	}

	// Verify codegen task (command)
	codegen, ok := tasks.Get("codegen")
	if !ok {
		t.Fatal("expected 'codegen' task to exist")
	}
	codegenCmd, ok := codegen.(CommandTask)
	if !ok {
		t.Fatalf("codegen: want CommandTask, got %T", codegen)
	}
	cmd := codegenCmd.Cmd()
	if len(cmd) < 1 || cmd[0] != "morphir" {
		t.Errorf("codegen.Cmd: want [morphir gen --target Scala], got %v", cmd)
	}
	if pre := codegen.Pre(); len(pre) != 1 || pre[0] != "compile" {
		t.Errorf("codegen.Pre: want [compile], got %v", pre)
	}
	if post := codegen.Post(); len(post) != 1 || post[0] != "test" {
		t.Errorf("codegen.Post: want [test], got %v", post)
	}
}

// Helper functions for tests
func writeFile(path, content string) error {
	return os.WriteFile(path, []byte(content), 0644)
}

func mkdir(path string) error {
	return os.MkdirAll(path, 0755)
}
