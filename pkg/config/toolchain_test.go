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
