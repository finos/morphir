package toolchain

import "testing"

func TestPlanBuilderBuild(t *testing.T) {
	registry := NewRegistry()
	registry.RegisterTarget(Target{Name: "make", Produces: []string{"morphir-ir"}})
	registry.RegisterTarget(Target{Name: "gen", Requires: []string{"morphir-ir"}, Produces: []string{"generated-code"}})

	registry.Register(Toolchain{
		Name: "tc",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
				Outputs: map[string]OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
			{
				Name:     "gen",
				Fulfills: []string{"gen"},
				Variants: []string{"scala"},
				Inputs: InputSpec{
					Artifacts: map[string]string{"ir": "@tc/make:ir"},
				},
				Outputs: map[string]OutputSpec{
					"out": {Path: "generated", Type: "generated-code"},
				},
			},
		},
	})

	workflows := map[string]Workflow{
		"build": {
			Name: "build",
			Stages: []WorkflowStage{
				{Name: "compile", Targets: []string{"make"}},
				{Name: "generate", Targets: []string{"gen:scala"}},
			},
		},
	}

	enablement := EnablementConfig{
		ExplicitEnabled: map[string]bool{"tc": true},
	}
	builder := NewPlanBuilderWithEnablement(registry, workflows, enablement)
	plan, err := builder.Build("build")
	if err != nil {
		t.Fatalf("expected plan build to succeed, got error: %v", err)
	}

	if len(plan.Stages) != 2 {
		t.Fatalf("expected 2 stages, got %d", len(plan.Stages))
	}
	if len(plan.Stages[0].Tasks) != 1 {
		t.Fatalf("expected 1 task in stage 0, got %d", len(plan.Stages[0].Tasks))
	}

	genKey := TaskKey{Toolchain: "tc", Task: "gen", Variant: "scala"}
	genTask, ok := plan.Tasks[genKey]
	if !ok {
		t.Fatalf("expected gen task %s to be in plan", genKey.String())
	}
	if len(genTask.DependsOn) != 1 || genTask.DependsOn[0].Task != "make" {
		t.Fatalf("expected gen task to depend on make, got %+v", genTask.DependsOn)
	}
}

func TestPlanBuilderRequiresVariant(t *testing.T) {
	registry := NewRegistry()
	registry.RegisterTarget(Target{Name: "gen", Produces: []string{"generated-code"}})
	registry.Register(Toolchain{
		Name: "tc",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "gen",
				Fulfills: []string{"gen"},
				Variants: []string{"scala"},
			},
		},
	})

	workflows := map[string]Workflow{
		"build": {
			Name: "build",
			Stages: []WorkflowStage{
				{Name: "generate", Targets: []string{"gen"}},
			},
		},
	}

	enablement := EnablementConfig{
		ExplicitEnabled: map[string]bool{"tc": true},
	}
	builder := NewPlanBuilderWithEnablement(registry, workflows, enablement)
	if _, err := builder.Build("build"); err == nil {
		t.Fatal("expected error for missing variant, got nil")
	}
}

func TestPlanBuilderStageOrderValidation(t *testing.T) {
	registry := NewRegistry()
	registry.RegisterTarget(Target{Name: "make", Produces: []string{"morphir-ir"}})
	registry.RegisterTarget(Target{Name: "gen", Requires: []string{"morphir-ir"}, Produces: []string{"generated-code"}})
	registry.Register(Toolchain{
		Name: "tc",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
				Outputs: map[string]OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
			{
				Name:     "gen",
				Fulfills: []string{"gen"},
				Outputs: map[string]OutputSpec{
					"out": {Path: "generated", Type: "generated-code"},
				},
			},
		},
	})

	workflows := map[string]Workflow{
		"build": {
			Name: "build",
			Stages: []WorkflowStage{
				{Name: "generate", Targets: []string{"gen"}},
				{Name: "compile", Targets: []string{"make"}},
			},
		},
	}

	enablement := EnablementConfig{
		ExplicitEnabled: map[string]bool{"tc": true},
	}
	builder := NewPlanBuilderWithEnablement(registry, workflows, enablement)
	if _, err := builder.Build("build"); err == nil {
		t.Fatal("expected error for invalid stage order, got nil")
	}
}

func TestPlanBuilderMultipleToolchainsFulfillTarget(t *testing.T) {
	// Test that when multiple enabled toolchains fulfill the same target,
	// all of them are included in the plan (not an error).
	registry := NewRegistry()
	registry.RegisterTarget(Target{Name: "make", Produces: []string{"morphir-ir"}})

	// Register two toolchains that both fulfill "make"
	registry.Register(Toolchain{
		Name: "tc-elm",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
				Outputs: map[string]OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
		},
	})
	registry.Register(Toolchain{
		Name: "tc-go",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
				Outputs: map[string]OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
		},
	})

	workflows := map[string]Workflow{
		"build": {
			Name: "build",
			Stages: []WorkflowStage{
				{Name: "compile", Targets: []string{"make"}},
			},
		},
	}

	// Enable both toolchains
	enablement := EnablementConfig{
		ExplicitEnabled: map[string]bool{
			"tc-elm": true,
			"tc-go":  true,
		},
	}
	builder := NewPlanBuilderWithEnablement(registry, workflows, enablement)
	plan, err := builder.Build("build")
	if err != nil {
		t.Fatalf("expected plan build to succeed with multiple toolchains, got error: %v", err)
	}

	// Verify both tasks are in the plan
	if len(plan.Tasks) != 2 {
		t.Fatalf("expected 2 tasks in plan, got %d", len(plan.Tasks))
	}
	if len(plan.Stages[0].Tasks) != 2 {
		t.Fatalf("expected 2 tasks in stage 0, got %d", len(plan.Stages[0].Tasks))
	}

	// Verify both toolchains are represented
	elmKey := TaskKey{Toolchain: "tc-elm", Task: "make", Variant: ""}
	goKey := TaskKey{Toolchain: "tc-go", Task: "make", Variant: ""}
	if _, ok := plan.Tasks[elmKey]; !ok {
		t.Fatalf("expected tc-elm/make to be in plan")
	}
	if _, ok := plan.Tasks[goKey]; !ok {
		t.Fatalf("expected tc-go/make to be in plan")
	}
}

func TestPlanBuilderOnlyEnabledToolchainsRun(t *testing.T) {
	// Test that disabled toolchains are excluded from the plan.
	registry := NewRegistry()
	registry.RegisterTarget(Target{Name: "make", Produces: []string{"morphir-ir"}})

	registry.Register(Toolchain{
		Name: "tc-elm",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
				Outputs: map[string]OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
		},
	})
	registry.Register(Toolchain{
		Name: "tc-go",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
				Outputs: map[string]OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
		},
	})

	workflows := map[string]Workflow{
		"build": {
			Name: "build",
			Stages: []WorkflowStage{
				{Name: "compile", Targets: []string{"make"}},
			},
		},
	}

	// Only enable tc-elm, disable tc-go explicitly
	enablement := EnablementConfig{
		ExplicitEnabled: map[string]bool{
			"tc-elm": true,
			"tc-go":  false,
		},
	}
	builder := NewPlanBuilderWithEnablement(registry, workflows, enablement)
	plan, err := builder.Build("build")
	if err != nil {
		t.Fatalf("expected plan build to succeed, got error: %v", err)
	}

	// Only tc-elm should be in the plan
	if len(plan.Tasks) != 1 {
		t.Fatalf("expected 1 task in plan, got %d", len(plan.Tasks))
	}

	elmKey := TaskKey{Toolchain: "tc-elm", Task: "make", Variant: ""}
	if _, ok := plan.Tasks[elmKey]; !ok {
		t.Fatalf("expected tc-elm/make to be in plan")
	}

	goKey := TaskKey{Toolchain: "tc-go", Task: "make", Variant: ""}
	if _, ok := plan.Tasks[goKey]; ok {
		t.Fatalf("expected tc-go/make NOT to be in plan (toolchain disabled)")
	}
}

func TestPlanBuilderDirectTaskReference(t *testing.T) {
	// Test that direct task references (toolchain/task) bypass target resolution
	registry := NewRegistry()
	registry.RegisterTarget(Target{Name: "make", Produces: []string{"morphir-ir"}})

	registry.Register(Toolchain{
		Name: "tc-elm",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
				Outputs: map[string]OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
		},
	})
	registry.Register(Toolchain{
		Name: "tc-go",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
				Outputs: map[string]OutputSpec{
					"ir": {Path: "module.ir.json", Type: "morphir-ir"},
				},
			},
		},
	})

	// Use direct task reference instead of target
	workflows := map[string]Workflow{
		"build": {
			Name: "build",
			Stages: []WorkflowStage{
				{Name: "compile", Targets: []string{"tc-elm/make"}}, // Direct reference
			},
		},
	}

	// Enable both toolchains
	enablement := EnablementConfig{
		ExplicitEnabled: map[string]bool{
			"tc-elm": true,
			"tc-go":  true,
		},
	}
	builder := NewPlanBuilderWithEnablement(registry, workflows, enablement)
	plan, err := builder.Build("build")
	if err != nil {
		t.Fatalf("expected plan build to succeed, got error: %v", err)
	}

	// Only tc-elm/make should be in the plan (direct reference)
	if len(plan.Tasks) != 1 {
		t.Fatalf("expected 1 task in plan with direct reference, got %d", len(plan.Tasks))
	}

	elmKey := TaskKey{Toolchain: "tc-elm", Task: "make", Variant: ""}
	if _, ok := plan.Tasks[elmKey]; !ok {
		t.Fatalf("expected tc-elm/make to be in plan")
	}
}

func TestPlanBuilderDirectTaskReferenceWithVariant(t *testing.T) {
	// Test direct task references with variants
	registry := NewRegistry()

	registry.Register(Toolchain{
		Name: "tc",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "gen",
				Fulfills: []string{"gen"},
				Variants: []string{"scala", "typescript"},
				Outputs: map[string]OutputSpec{
					"out": {Path: "generated", Type: "generated-code"},
				},
			},
		},
	})

	// Use direct task reference with variant
	workflows := map[string]Workflow{
		"build": {
			Name: "build",
			Stages: []WorkflowStage{
				{Name: "generate", Targets: []string{"tc/gen:scala"}}, // Direct reference with variant
			},
		},
	}

	enablement := EnablementConfig{
		ExplicitEnabled: map[string]bool{"tc": true},
	}
	builder := NewPlanBuilderWithEnablement(registry, workflows, enablement)
	plan, err := builder.Build("build")
	if err != nil {
		t.Fatalf("expected plan build to succeed, got error: %v", err)
	}

	if len(plan.Tasks) != 1 {
		t.Fatalf("expected 1 task in plan, got %d", len(plan.Tasks))
	}

	key := TaskKey{Toolchain: "tc", Task: "gen", Variant: "scala"}
	task, ok := plan.Tasks[key]
	if !ok {
		t.Fatalf("expected tc/gen:scala to be in plan")
	}
	if task.Variant != "scala" {
		t.Fatalf("expected variant 'scala', got %q", task.Variant)
	}
}

func TestPlanBuilderDirectTaskReferenceDisabledToolchain(t *testing.T) {
	// Test that direct task references still respect enablement
	registry := NewRegistry()

	registry.Register(Toolchain{
		Name: "tc",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
			},
		},
	})

	workflows := map[string]Workflow{
		"build": {
			Name: "build",
			Stages: []WorkflowStage{
				{Name: "compile", Targets: []string{"tc/make"}},
			},
		},
	}

	// Toolchain explicitly disabled
	enablement := EnablementConfig{
		ExplicitEnabled: map[string]bool{"tc": false},
	}
	builder := NewPlanBuilderWithEnablement(registry, workflows, enablement)
	_, err := builder.Build("build")
	if err == nil {
		t.Fatal("expected error when using direct reference to disabled toolchain")
	}
}

func TestPlanBuilderDirectTaskReferenceNotFound(t *testing.T) {
	// Test error handling for non-existent task
	registry := NewRegistry()

	registry.Register(Toolchain{
		Name: "tc",
		Type: ToolchainTypeExternal,
		Tasks: []TaskDef{
			{
				Name:     "make",
				Fulfills: []string{"make"},
			},
		},
	})

	workflows := map[string]Workflow{
		"build": {
			Name: "build",
			Stages: []WorkflowStage{
				{Name: "compile", Targets: []string{"tc/nonexistent"}},
			},
		},
	}

	enablement := EnablementConfig{
		ExplicitEnabled: map[string]bool{"tc": true},
	}
	builder := NewPlanBuilderWithEnablement(registry, workflows, enablement)
	_, err := builder.Build("build")
	if err == nil {
		t.Fatal("expected error when using direct reference to non-existent task")
	}
}
