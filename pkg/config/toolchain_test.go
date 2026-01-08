package config

import (
	"testing"
)

func TestToolchainsSectionGet(t *testing.T) {
	t.Run("existing toolchain", func(t *testing.T) {
		tc := ToolchainConfig{name: "test-toolchain"}
		section := ToolchainsSection{
			definitions: map[string]ToolchainConfig{
				"test-toolchain": tc,
			},
		}

		result, ok := section.Get("test-toolchain")
		if !ok {
			t.Fatal("expected toolchain to be found")
		}

		if result.Name() != "test-toolchain" {
			t.Errorf("expected name 'test-toolchain', got '%s'", result.Name())
		}
	})

	t.Run("non-existing toolchain", func(t *testing.T) {
		section := ToolchainsSection{
			definitions: map[string]ToolchainConfig{},
		}

		_, ok := section.Get("nonexistent")
		if ok {
			t.Error("expected toolchain not to be found")
		}
	})

	t.Run("nil definitions", func(t *testing.T) {
		section := ToolchainsSection{definitions: nil}

		_, ok := section.Get("test")
		if ok {
			t.Error("expected toolchain not to be found with nil definitions")
		}
	})
}

func TestToolchainsSectionNames(t *testing.T) {
	tc1 := ToolchainConfig{name: "toolchain-a"}
	tc2 := ToolchainConfig{name: "toolchain-b"}
	section := ToolchainsSection{
		definitions: map[string]ToolchainConfig{
			"toolchain-a": tc1,
			"toolchain-b": tc2,
		},
	}

	names := section.Names()
	if len(names) != 2 {
		t.Errorf("expected 2 toolchain names, got %d", len(names))
	}

	found := make(map[string]bool)
	for _, name := range names {
		found[name] = true
	}

	if !found["toolchain-a"] || !found["toolchain-b"] {
		t.Errorf("expected toolchains 'toolchain-a' and 'toolchain-b', got %v", names)
	}
}

func TestToolchainConfigAccessors(t *testing.T) {
	tc := ToolchainConfig{
		name:       "test-toolchain",
		version:    "1.0.0",
		workingDir: "/test/dir",
		timeout:    "5m",
		env: map[string]string{
			"KEY": "value",
		},
		acquire: AcquireConfig{
			backend:    "path",
			packageVal: "test-package",
			version:    "1.0.0",
			executable: "test-exec",
		},
		tasks: map[string]ToolchainTaskConfig{
			"task1": {exec: "echo"},
		},
	}

	if tc.Name() != "test-toolchain" {
		t.Errorf("expected name 'test-toolchain', got '%s'", tc.Name())
	}

	if tc.Version() != "1.0.0" {
		t.Errorf("expected version '1.0.0', got '%s'", tc.Version())
	}

	if tc.WorkingDir() != "/test/dir" {
		t.Errorf("expected working dir '/test/dir', got '%s'", tc.WorkingDir())
	}

	if tc.Timeout() != "5m" {
		t.Errorf("expected timeout '5m', got '%s'", tc.Timeout())
	}

	env := tc.Env()
	if env["KEY"] != "value" {
		t.Errorf("expected env KEY='value', got '%s'", env["KEY"])
	}

	acquire := tc.Acquire()
	if acquire.Backend() != "path" {
		t.Errorf("expected backend 'path', got '%s'", acquire.Backend())
	}

	if acquire.Package() != "test-package" {
		t.Errorf("expected package 'test-package', got '%s'", acquire.Package())
	}

	tasks := tc.Tasks()
	if len(tasks) != 1 {
		t.Errorf("expected 1 task, got %d", len(tasks))
	}
}

func TestFromMapWithToolchains(t *testing.T) {
	configMap := map[string]any{
		"toolchain": map[string]any{
			"test-toolchain": map[string]any{
				"version": "1.0.0",
				"acquire": map[string]any{
					"backend":    "path",
					"executable": "test-exec",
				},
				"env": map[string]any{
					"TEST_VAR": "test-value",
				},
				"working_dir": "/test/dir",
				"timeout":     "5m",
				"tasks": map[string]any{
					"make": map[string]any{
						"exec": "test-exec",
						"args": []any{"make", "-o", "{outputs.ir}"},
						"inputs": map[string]any{
							"files": []any{"src/**/*.elm"},
						},
						"outputs": map[string]any{
							"ir": map[string]any{
								"path": "morphir-ir.json",
								"type": "morphir-ir",
							},
						},
						"fulfills": []any{"make"},
						"variants": []any{"scala", "typescript"},
					},
				},
			},
		},
	}

	cfg := FromMap(configMap)

	tc, ok := cfg.Toolchains().Get("test-toolchain")
	if !ok {
		t.Fatal("expected toolchain 'test-toolchain' to be loaded")
	}

	if tc.Version() != "1.0.0" {
		t.Errorf("expected version '1.0.0', got '%s'", tc.Version())
	}

	acquire := tc.Acquire()
	if acquire.Backend() != "path" {
		t.Errorf("expected backend 'path', got '%s'", acquire.Backend())
	}

	if acquire.Executable() != "test-exec" {
		t.Errorf("expected executable 'test-exec', got '%s'", acquire.Executable())
	}

	env := tc.Env()
	if env["TEST_VAR"] != "test-value" {
		t.Errorf("expected TEST_VAR='test-value', got '%s'", env["TEST_VAR"])
	}

	tasks := tc.Tasks()
	makeTask, ok := tasks["make"]
	if !ok {
		t.Fatal("expected 'make' task to be loaded")
	}

	if makeTask.Exec() != "test-exec" {
		t.Errorf("expected exec 'test-exec', got '%s'", makeTask.Exec())
	}

	args := makeTask.Args()
	if len(args) != 3 {
		t.Errorf("expected 3 args, got %d", len(args))
	}

	outputs := makeTask.Outputs()
	irOutput, ok := outputs["ir"]
	if !ok {
		t.Fatal("expected 'ir' output to be loaded")
	}

	if irOutput.Path() != "morphir-ir.json" {
		t.Errorf("expected output path 'morphir-ir.json', got '%s'", irOutput.Path())
	}

	if irOutput.Type() != "morphir-ir" {
		t.Errorf("expected output type 'morphir-ir', got '%s'", irOutput.Type())
	}

	fulfills := makeTask.Fulfills()
	if len(fulfills) != 1 || fulfills[0] != "make" {
		t.Errorf("expected fulfills ['make'], got %v", fulfills)
	}

	variants := makeTask.Variants()
	if len(variants) != 2 {
		t.Errorf("expected 2 variants, got %d", len(variants))
	}
}

func TestToolchainsSectionLen(t *testing.T) {
	t.Run("with toolchains", func(t *testing.T) {
		tc1 := ToolchainConfig{name: "tc1"}
		tc2 := ToolchainConfig{name: "tc2"}
		section := ToolchainsSection{
			definitions: map[string]ToolchainConfig{
				"tc1": tc1,
				"tc2": tc2,
			},
		}

		if section.Len() != 2 {
			t.Errorf("expected length 2, got %d", section.Len())
		}
	})

	t.Run("empty section", func(t *testing.T) {
		section := ToolchainsSection{definitions: map[string]ToolchainConfig{}}
		if section.Len() != 0 {
			t.Errorf("expected length 0, got %d", section.Len())
		}
	})

	t.Run("nil definitions", func(t *testing.T) {
		section := ToolchainsSection{definitions: nil}
		if section.Len() != 0 {
			t.Errorf("expected length 0, got %d", section.Len())
		}
	})
}

func TestToolchainConfigEmptyFields(t *testing.T) {
	tc := ToolchainConfig{}

	env := tc.Env()
	if env != nil {
		t.Error("expected nil env for empty config")
	}

	tasks := tc.Tasks()
	if tasks != nil {
		t.Error("expected nil tasks for empty config")
	}
}

func TestAcquireConfigAccessors(t *testing.T) {
	cfg := AcquireConfig{
		backend:    "npx",
		packageVal: "morphir-elm",
		version:    "^2.90.0",
		executable: "morphir-elm",
	}

	if cfg.Backend() != "npx" {
		t.Errorf("expected backend 'npx', got '%s'", cfg.Backend())
	}

	if cfg.Package() != "morphir-elm" {
		t.Errorf("expected package 'morphir-elm', got '%s'", cfg.Package())
	}

	if cfg.Version() != "^2.90.0" {
		t.Errorf("expected version '^2.90.0', got '%s'", cfg.Version())
	}

	if cfg.Executable() != "morphir-elm" {
		t.Errorf("expected executable 'morphir-elm', got '%s'", cfg.Executable())
	}
}

func TestToolchainTaskConfigAccessors(t *testing.T) {
	cfg := ToolchainTaskConfig{
		exec: "test-exec",
		args: []string{"arg1", "arg2"},
		inputs: InputsConfig{
			files:     []string{"src/**/*.elm"},
			artifacts: map[string]string{"ir": "@toolchain/task:ir"},
		},
		outputs: map[string]OutputConfig{
			"out1": {path: "output.json", typeVal: "json"},
		},
		fulfills: []string{"make"},
		variants: []string{"scala", "typescript"},
		env: map[string]string{
			"VAR": "value",
		},
	}

	if cfg.Exec() != "test-exec" {
		t.Errorf("expected exec 'test-exec', got '%s'", cfg.Exec())
	}

	args := cfg.Args()
	if len(args) != 2 || args[0] != "arg1" {
		t.Errorf("expected args ['arg1', 'arg2'], got %v", args)
	}

	inputs := cfg.Inputs()
	files := inputs.Files()
	if len(files) != 1 || files[0] != "src/**/*.elm" {
		t.Errorf("expected files ['src/**/*.elm'], got %v", files)
	}

	artifacts := inputs.Artifacts()
	if artifacts["ir"] != "@toolchain/task:ir" {
		t.Errorf("expected artifact reference, got %v", artifacts)
	}

	outputs := cfg.Outputs()
	if len(outputs) != 1 {
		t.Errorf("expected 1 output, got %d", len(outputs))
	}

	fulfills := cfg.Fulfills()
	if len(fulfills) != 1 || fulfills[0] != "make" {
		t.Errorf("expected fulfills ['make'], got %v", fulfills)
	}

	variants := cfg.Variants()
	if len(variants) != 2 {
		t.Errorf("expected 2 variants, got %d", len(variants))
	}

	env := cfg.Env()
	if env["VAR"] != "value" {
		t.Errorf("expected env VAR='value', got '%s'", env["VAR"])
	}
}

func TestToolchainTaskConfigEmptyFields(t *testing.T) {
	cfg := ToolchainTaskConfig{}

	if cfg.Args() != nil {
		t.Error("expected nil args for empty config")
	}

	if cfg.Outputs() != nil {
		t.Error("expected nil outputs for empty config")
	}

	if cfg.Fulfills() != nil {
		t.Error("expected nil fulfills for empty config")
	}

	if cfg.Variants() != nil {
		t.Error("expected nil variants for empty config")
	}

	if cfg.Env() != nil {
		t.Error("expected nil env for empty config")
	}
}

func TestInputsConfigAccessors(t *testing.T) {
	cfg := InputsConfig{
		files:     []string{"file1.txt", "file2.txt"},
		artifacts: map[string]string{"ir": "@toolchain/task:ir"},
	}

	files := cfg.Files()
	if len(files) != 2 || files[0] != "file1.txt" {
		t.Errorf("expected files ['file1.txt', 'file2.txt'], got %v", files)
	}

	artifacts := cfg.Artifacts()
	if artifacts["ir"] != "@toolchain/task:ir" {
		t.Errorf("expected artifact reference, got %v", artifacts)
	}
}

func TestInputsConfigEmptyFields(t *testing.T) {
	cfg := InputsConfig{}

	if cfg.Files() != nil {
		t.Error("expected nil files for empty config")
	}

	if cfg.Artifacts() != nil {
		t.Error("expected nil artifacts for empty config")
	}
}

func TestOutputConfigAccessors(t *testing.T) {
	cfg := OutputConfig{
		path:    "output.json",
		typeVal: "morphir-ir",
	}

	if cfg.Path() != "output.json" {
		t.Errorf("expected path 'output.json', got '%s'", cfg.Path())
	}

	if cfg.Type() != "morphir-ir" {
		t.Errorf("expected type 'morphir-ir', got '%s'", cfg.Type())
	}
}

func TestToolchainConfigDefensiveCopy(t *testing.T) {
	t.Run("env defensive copy", func(t *testing.T) {
		originalEnv := map[string]string{"KEY": "value"}
		tc := ToolchainConfig{env: originalEnv}

		env := tc.Env()
		env["KEY"] = "modified"

		// Original should be unchanged
		if originalEnv["KEY"] != "value" {
			t.Error("original env was modified")
		}

		// Second call should return original value
		env2 := tc.Env()
		if env2["KEY"] != "value" {
			t.Error("defensive copy not working")
		}
	})

	t.Run("tasks defensive copy", func(t *testing.T) {
		originalTasks := map[string]ToolchainTaskConfig{
			"task1": {exec: "echo"},
		}
		tc := ToolchainConfig{tasks: originalTasks}

		tasks := tc.Tasks()
		delete(tasks, "task1")

		// Original should be unchanged
		if _, ok := originalTasks["task1"]; !ok {
			t.Error("original tasks was modified")
		}

		// Second call should return original
		tasks2 := tc.Tasks()
		if len(tasks2) != 1 {
			t.Error("defensive copy not working")
		}
	})
}

func TestToolchainTaskConfigDefensiveCopy(t *testing.T) {
	t.Run("args defensive copy", func(t *testing.T) {
		originalArgs := []string{"arg1", "arg2"}
		cfg := ToolchainTaskConfig{args: originalArgs}

		args := cfg.Args()
		args[0] = "modified"

		// Original should be unchanged
		if originalArgs[0] != "arg1" {
			t.Error("original args was modified")
		}
	})

	t.Run("outputs defensive copy", func(t *testing.T) {
		originalOutputs := map[string]OutputConfig{
			"out1": {path: "output.json"},
		}
		cfg := ToolchainTaskConfig{outputs: originalOutputs}

		outputs := cfg.Outputs()
		delete(outputs, "out1")

		// Original should be unchanged
		if _, ok := originalOutputs["out1"]; !ok {
			t.Error("original outputs was modified")
		}
	})

	t.Run("fulfills defensive copy", func(t *testing.T) {
		originalFulfills := []string{"make"}
		cfg := ToolchainTaskConfig{fulfills: originalFulfills}

		fulfills := cfg.Fulfills()
		fulfills[0] = "modified"

		// Original should be unchanged
		if originalFulfills[0] != "make" {
			t.Error("original fulfills was modified")
		}
	})

	t.Run("variants defensive copy", func(t *testing.T) {
		originalVariants := []string{"scala"}
		cfg := ToolchainTaskConfig{variants: originalVariants}

		variants := cfg.Variants()
		variants[0] = "modified"

		// Original should be unchanged
		if originalVariants[0] != "scala" {
			t.Error("original variants was modified")
		}
	})

	t.Run("env defensive copy", func(t *testing.T) {
		originalEnv := map[string]string{"KEY": "value"}
		cfg := ToolchainTaskConfig{env: originalEnv}

		env := cfg.Env()
		env["KEY"] = "modified"

		// Original should be unchanged
		if originalEnv["KEY"] != "value" {
			t.Error("original env was modified")
		}
	})
}

func TestInputsConfigDefensiveCopy(t *testing.T) {
	t.Run("files defensive copy", func(t *testing.T) {
		originalFiles := []string{"file1.txt"}
		cfg := InputsConfig{files: originalFiles}

		files := cfg.Files()
		files[0] = "modified"

		// Original should be unchanged
		if originalFiles[0] != "file1.txt" {
			t.Error("original files was modified")
		}
	})

	t.Run("artifacts defensive copy", func(t *testing.T) {
		originalArtifacts := map[string]string{"ir": "@toolchain/task:ir"}
		cfg := InputsConfig{artifacts: originalArtifacts}

		artifacts := cfg.Artifacts()
		artifacts["ir"] = "modified"

		// Original should be unchanged
		if originalArtifacts["ir"] != "@toolchain/task:ir" {
			t.Error("original artifacts was modified")
		}
	})
}

func TestFromMapWithToolchainsInputArtifacts(t *testing.T) {
	configMap := map[string]any{
		"toolchain": map[string]any{
			"test-toolchain": map[string]any{
				"tasks": map[string]any{
					"gen": map[string]any{
						"exec": "test-exec",
						"inputs": map[string]any{
							"files": []any{"file1.txt"},
							"artifacts": map[string]any{
								"ir": "@toolchain/make:ir",
							},
						},
					},
				},
			},
		},
	}

	cfg := FromMap(configMap)

	tc, ok := cfg.Toolchains().Get("test-toolchain")
	if !ok {
		t.Fatal("expected toolchain to be loaded")
	}

	tasks := tc.Tasks()
	genTask, ok := tasks["gen"]
	if !ok {
		t.Fatal("expected 'gen' task to be loaded")
	}

	inputs := genTask.Inputs()
	files := inputs.Files()
	if len(files) != 1 || files[0] != "file1.txt" {
		t.Errorf("expected files ['file1.txt'], got %v", files)
	}

	artifacts := inputs.Artifacts()
	if artifacts["ir"] != "@toolchain/make:ir" {
		t.Errorf("expected artifact reference '@toolchain/make:ir', got '%s'", artifacts["ir"])
	}
}

func TestFromMapWithToolchainsSimpleInputs(t *testing.T) {
	// Test parsing inputs as a simple array
	configMap := map[string]any{
		"toolchain": map[string]any{
			"test-toolchain": map[string]any{
				"tasks": map[string]any{
					"make": map[string]any{
						"exec":   "test-exec",
						"inputs": []any{"file1.txt", "file2.txt"},
					},
				},
			},
		},
	}

	cfg := FromMap(configMap)

	tc, ok := cfg.Toolchains().Get("test-toolchain")
	if !ok {
		t.Fatal("expected toolchain to be loaded")
	}

	tasks := tc.Tasks()
	makeTask, ok := tasks["make"]
	if !ok {
		t.Fatal("expected 'make' task to be loaded")
	}

	inputs := makeTask.Inputs()
	files := inputs.Files()
	if len(files) != 2 {
		t.Errorf("expected 2 files, got %d", len(files))
	}
}
