package toolchain_test

import (
	"testing"
	"time"

	"github.com/finos/morphir/pkg/config"
	"github.com/finos/morphir/pkg/toolchain"
)

func TestLoadWorkflowsFromConfig(t *testing.T) {
	// Create a config with workflows
	cfg := config.FromMap(map[string]any{
		"workflows": map[string]any{
			"build": map[string]any{
				"description": "Standard build workflow",
				"stages": []any{
					map[string]any{
						"name":     "frontend",
						"targets":  []any{"make"},
						"parallel": false,
					},
					map[string]any{
						"name":     "backend",
						"targets":  []any{"gen:scala", "gen:typescript"},
						"parallel": true,
					},
				},
			},
			"ci": map[string]any{
				"description": "CI pipeline",
				"extends":     "build",
				"stages": []any{
					map[string]any{
						"name":      "test",
						"targets":   []any{"validate"},
						"condition": "always()",
					},
				},
			},
		},
	})

	workflows := toolchain.LoadWorkflowsFromConfig(cfg)

	if len(workflows) != 2 {
		t.Fatalf("expected 2 workflows, got %d", len(workflows))
	}

	// Find workflows by name (order may vary)
	var buildWf, ciWf toolchain.Workflow
	for _, wf := range workflows {
		switch wf.Name {
		case "build":
			buildWf = wf
		case "ci":
			ciWf = wf
		}
	}

	// Check build workflow
	if buildWf.Name != "build" {
		t.Error("build workflow not found")
	}
	if buildWf.Description != "Standard build workflow" {
		t.Errorf("expected description 'Standard build workflow', got %q", buildWf.Description)
	}
	if len(buildWf.Stages) != 2 {
		t.Errorf("expected 2 stages, got %d", len(buildWf.Stages))
	}

	// Check frontend stage
	if buildWf.Stages[0].Name != "frontend" {
		t.Errorf("expected stage name 'frontend', got %q", buildWf.Stages[0].Name)
	}
	if buildWf.Stages[0].Parallel {
		t.Error("frontend stage should not be parallel")
	}

	// Check backend stage
	if buildWf.Stages[1].Name != "backend" {
		t.Errorf("expected stage name 'backend', got %q", buildWf.Stages[1].Name)
	}
	if !buildWf.Stages[1].Parallel {
		t.Error("backend stage should be parallel")
	}
	if len(buildWf.Stages[1].Targets) != 2 {
		t.Errorf("expected 2 targets, got %d", len(buildWf.Stages[1].Targets))
	}

	// Check CI workflow
	if ciWf.Name != "ci" {
		t.Error("ci workflow not found")
	}
	if ciWf.Extends != "build" {
		t.Errorf("expected extends 'build', got %q", ciWf.Extends)
	}
	if len(ciWf.Stages) != 1 {
		t.Errorf("expected 1 stage, got %d", len(ciWf.Stages))
	}
	if ciWf.Stages[0].Condition != "always()" {
		t.Errorf("expected condition 'always()', got %q", ciWf.Stages[0].Condition)
	}
}

func TestLoadWorkflowsFromConfig_Empty(t *testing.T) {
	cfg := config.Default()
	workflows := toolchain.LoadWorkflowsFromConfig(cfg)

	if workflows != nil {
		t.Errorf("expected nil workflows for empty config, got %v", workflows)
	}
}

func TestWorkflowFromConfig(t *testing.T) {
	cfg := config.FromMap(map[string]any{
		"workflows": map[string]any{
			"test": map[string]any{
				"description": "Test workflow",
				"extends":     "base",
				"stages": []any{
					map[string]any{
						"name":    "stage1",
						"targets": []any{"target1", "target2"},
					},
				},
			},
		},
	})

	wfCfg, ok := cfg.Workflows().Get("test")
	if !ok {
		t.Fatal("test workflow not found in config")
	}

	wf := toolchain.WorkflowFromConfig(wfCfg)

	if wf.Name != "test" {
		t.Errorf("expected name 'test', got %q", wf.Name)
	}
	if wf.Description != "Test workflow" {
		t.Errorf("expected description 'Test workflow', got %q", wf.Description)
	}
	if wf.Extends != "base" {
		t.Errorf("expected extends 'base', got %q", wf.Extends)
	}
	if len(wf.Stages) != 1 {
		t.Errorf("expected 1 stage, got %d", len(wf.Stages))
	}
}

func TestLoadToolchainsFromConfig(t *testing.T) {
	cfg := config.FromMap(map[string]any{
		"toolchain": map[string]any{
			"morphir-elm": map[string]any{
				"version": "2.90.0",
				"timeout": "5m",
				"acquire": map[string]any{
					"backend":    "npx",
					"package":    "morphir-elm",
					"version":    "2.90.0",
					"executable": "morphir-elm",
				},
				"env": map[string]any{
					"NODE_ENV": "production",
				},
				"working_dir": ".",
				"tasks": map[string]any{
					"make": map[string]any{
						"exec":     "morphir-elm",
						"args":     []any{"make", "-o", "{outputs.ir}"},
						"fulfills": []any{"make"},
						"variants": []any{"Scala", "TypeScript"},
						"inputs": map[string]any{
							"files": []any{"elm.json", "src/**/*.elm"},
						},
						"outputs": map[string]any{
							"ir": map[string]any{
								"path": "morphir-ir.json",
								"type": "morphir-ir",
							},
						},
					},
				},
			},
		},
	})

	toolchains := toolchain.LoadToolchainsFromConfig(cfg)

	if len(toolchains) != 1 {
		t.Fatalf("expected 1 toolchain, got %d", len(toolchains))
	}

	tc := toolchains[0]

	if tc.Name != "morphir-elm" {
		t.Errorf("expected name 'morphir-elm', got %q", tc.Name)
	}
	if tc.Version != "2.90.0" {
		t.Errorf("expected version '2.90.0', got %q", tc.Version)
	}
	if tc.Timeout != 5*time.Minute {
		t.Errorf("expected timeout 5m, got %v", tc.Timeout)
	}
	if tc.Type != toolchain.ToolchainTypeExternal {
		t.Errorf("expected type external, got %v", tc.Type)
	}

	// Check acquire config
	if tc.Acquire.Backend != "npx" {
		t.Errorf("expected acquire backend 'npx', got %q", tc.Acquire.Backend)
	}
	if tc.Acquire.Package != "morphir-elm" {
		t.Errorf("expected acquire package 'morphir-elm', got %q", tc.Acquire.Package)
	}

	// Check env
	if tc.Env["NODE_ENV"] != "production" {
		t.Errorf("expected NODE_ENV 'production', got %q", tc.Env["NODE_ENV"])
	}

	// Check tasks
	if len(tc.Tasks) != 1 {
		t.Fatalf("expected 1 task, got %d", len(tc.Tasks))
	}

	var makeTask toolchain.TaskDef
	for _, task := range tc.Tasks {
		if task.Name == "make" {
			makeTask = task
		}
	}

	if makeTask.Name != "make" {
		t.Error("make task not found")
	}
	if makeTask.Exec != "morphir-elm" {
		t.Errorf("expected exec 'morphir-elm', got %q", makeTask.Exec)
	}
	if len(makeTask.Args) != 3 {
		t.Errorf("expected 3 args, got %d", len(makeTask.Args))
	}
	if len(makeTask.Fulfills) != 1 || makeTask.Fulfills[0] != "make" {
		t.Errorf("expected fulfills ['make'], got %v", makeTask.Fulfills)
	}
	if len(makeTask.Variants) != 2 {
		t.Errorf("expected 2 variants, got %d", len(makeTask.Variants))
	}

	// Check inputs
	if len(makeTask.Inputs.Files) != 2 {
		t.Errorf("expected 2 input files, got %d", len(makeTask.Inputs.Files))
	}

	// Check outputs
	if irOutput, ok := makeTask.Outputs["ir"]; !ok {
		t.Error("ir output not found")
	} else {
		if irOutput.Path != "morphir-ir.json" {
			t.Errorf("expected output path 'morphir-ir.json', got %q", irOutput.Path)
		}
		if irOutput.Type != "morphir-ir" {
			t.Errorf("expected output type 'morphir-ir', got %q", irOutput.Type)
		}
	}
}

func TestLoadToolchainsFromConfig_Empty(t *testing.T) {
	cfg := config.Default()
	toolchains := toolchain.LoadToolchainsFromConfig(cfg)

	if toolchains != nil {
		t.Errorf("expected nil toolchains for empty config, got %v", toolchains)
	}
}

func TestRegisterToolchainsFromConfig(t *testing.T) {
	cfg := config.FromMap(map[string]any{
		"toolchain": map[string]any{
			"test-tc": map[string]any{
				"version": "1.0.0",
				"acquire": map[string]any{
					"backend":    "path",
					"executable": "test-tool",
				},
			},
		},
	})

	registry := toolchain.NewRegistry()
	toolchain.RegisterToolchainsFromConfig(registry, cfg)

	tc, ok := registry.GetToolchain("test-tc")
	if !ok {
		t.Fatal("test-tc not found in registry")
	}
	if tc.Name != "test-tc" {
		t.Errorf("expected name 'test-tc', got %q", tc.Name)
	}
	if tc.Version != "1.0.0" {
		t.Errorf("expected version '1.0.0', got %q", tc.Version)
	}
}

func TestGetWorkflow(t *testing.T) {
	cfg := config.FromMap(map[string]any{
		"workflows": map[string]any{
			"build": map[string]any{
				"description": "Build workflow",
			},
		},
	})

	// Test found
	wf, ok := toolchain.GetWorkflow(cfg, "build")
	if !ok {
		t.Fatal("build workflow not found")
	}
	if wf.Name != "build" {
		t.Errorf("expected name 'build', got %q", wf.Name)
	}

	// Test not found
	_, ok = toolchain.GetWorkflow(cfg, "nonexistent")
	if ok {
		t.Error("expected nonexistent workflow to not be found")
	}
}

func TestGetToolchain(t *testing.T) {
	cfg := config.FromMap(map[string]any{
		"toolchain": map[string]any{
			"test-tc": map[string]any{
				"version": "1.0.0",
			},
		},
	})

	// Test found
	tc, ok := toolchain.GetToolchain(cfg, "test-tc")
	if !ok {
		t.Fatal("test-tc not found")
	}
	if tc.Name != "test-tc" {
		t.Errorf("expected name 'test-tc', got %q", tc.Name)
	}

	// Test not found
	_, ok = toolchain.GetToolchain(cfg, "nonexistent")
	if ok {
		t.Error("expected nonexistent toolchain to not be found")
	}
}

func TestTaskDefFromConfig_WithArtifactInputs(t *testing.T) {
	cfg := config.FromMap(map[string]any{
		"toolchain": map[string]any{
			"gen": map[string]any{
				"tasks": map[string]any{
					"gen-scala": map[string]any{
						"exec": "morphir-elm",
						"args": []any{"gen", "-t", "scala"},
						"inputs": map[string]any{
							"files":     []any{"src/**/*.elm"},
							"artifacts": map[string]any{"ir": "@morphir-elm/make:ir"},
						},
						"outputs": map[string]any{
							"code": map[string]any{
								"path": "generated/",
								"type": "generated-code",
							},
						},
					},
				},
			},
		},
	})

	toolchains := toolchain.LoadToolchainsFromConfig(cfg)
	if len(toolchains) != 1 {
		t.Fatalf("expected 1 toolchain, got %d", len(toolchains))
	}

	tc := toolchains[0]
	if len(tc.Tasks) != 1 {
		t.Fatalf("expected 1 task, got %d", len(tc.Tasks))
	}

	task := tc.Tasks[0]
	if len(task.Inputs.Files) != 1 {
		t.Errorf("expected 1 input file, got %d", len(task.Inputs.Files))
	}
	if task.Inputs.Artifacts["ir"] != "@morphir-elm/make:ir" {
		t.Errorf("expected artifact ref '@morphir-elm/make:ir', got %q", task.Inputs.Artifacts["ir"])
	}
}
