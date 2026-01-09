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

	builder := NewPlanBuilder(registry, workflows)
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

	builder := NewPlanBuilder(registry, workflows)
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

	builder := NewPlanBuilder(registry, workflows)
	if _, err := builder.Build("build"); err == nil {
		t.Fatal("expected error for invalid stage order, got nil")
	}
}
