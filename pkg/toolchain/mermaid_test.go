package toolchain_test

import (
	"strings"
	"testing"

	"github.com/finos/morphir/pkg/toolchain"
)

func TestPlanToMermaid_EmptyPlan(t *testing.T) {
	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "empty"},
		Stages:   []toolchain.PlanStage{},
		Tasks:    map[toolchain.TaskKey]*toolchain.PlanTask{},
	}

	result := toolchain.PlanToMermaid(plan)

	if !strings.HasPrefix(result, "flowchart TD\n") {
		t.Errorf("expected flowchart TD header, got: %s", result)
	}
}

func TestPlanToMermaid_SingleStage(t *testing.T) {
	taskKey := toolchain.TaskKey{Toolchain: "morphir-elm", Task: "make"}
	task := &toolchain.PlanTask{
		Key:       taskKey,
		Toolchain: "morphir-elm",
		Task:      "make",
	}

	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "build"},
		Stages: []toolchain.PlanStage{
			{
				Name:  "frontend",
				Tasks: []*toolchain.PlanTask{task},
			},
		},
		Tasks: map[toolchain.TaskKey]*toolchain.PlanTask{
			taskKey: task,
		},
	}

	result := toolchain.PlanToMermaid(plan)

	// Check for stage subgraph
	if !strings.Contains(result, `subgraph stage_0["Stage: frontend"]`) {
		t.Errorf("expected stage subgraph, got: %s", result)
	}

	// Check for task node
	if !strings.Contains(result, `morphir_elm_make["morphir-elm/make"]`) {
		t.Errorf("expected task node, got: %s", result)
	}
}

func TestPlanToMermaid_ParallelStage(t *testing.T) {
	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "build"},
		Stages: []toolchain.PlanStage{
			{
				Name:     "backend",
				Parallel: true,
				Tasks:    []*toolchain.PlanTask{},
			},
		},
		Tasks: map[toolchain.TaskKey]*toolchain.PlanTask{},
	}

	result := toolchain.PlanToMermaid(plan)

	if !strings.Contains(result, `"Stage: backend (parallel)"`) {
		t.Errorf("expected parallel indicator in stage label, got: %s", result)
	}
}

func TestPlanToMermaid_WithVariant(t *testing.T) {
	taskKey := toolchain.TaskKey{Toolchain: "morphir-elm", Task: "gen", Variant: "Scala"}
	task := &toolchain.PlanTask{
		Key:       taskKey,
		Toolchain: "morphir-elm",
		Task:      "gen",
		Variant:   "Scala",
	}

	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "build"},
		Stages: []toolchain.PlanStage{
			{
				Name:  "codegen",
				Tasks: []*toolchain.PlanTask{task},
			},
		},
		Tasks: map[toolchain.TaskKey]*toolchain.PlanTask{
			taskKey: task,
		},
	}

	result := toolchain.PlanToMermaid(plan)

	// Check for variant in node label
	if !strings.Contains(result, `"morphir-elm/gen (Scala)"`) {
		t.Errorf("expected variant in node label, got: %s", result)
	}

	// Check for variant in node ID
	if !strings.Contains(result, "morphir_elm_gen_Scala") {
		t.Errorf("expected variant in node ID, got: %s", result)
	}
}

func TestPlanToMermaid_WithDependencies(t *testing.T) {
	makeKey := toolchain.TaskKey{Toolchain: "morphir-elm", Task: "make"}
	genKey := toolchain.TaskKey{Toolchain: "morphir-elm", Task: "gen", Variant: "Scala"}

	makeTask := &toolchain.PlanTask{
		Key:        makeKey,
		Toolchain:  "morphir-elm",
		Task:       "make",
		StageIndex: 0,
	}
	genTask := &toolchain.PlanTask{
		Key:        genKey,
		Toolchain:  "morphir-elm",
		Task:       "gen",
		Variant:    "Scala",
		StageIndex: 1,
		DependsOn:  []toolchain.TaskKey{makeKey},
	}

	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "build"},
		Stages: []toolchain.PlanStage{
			{
				Name:  "frontend",
				Tasks: []*toolchain.PlanTask{makeTask},
			},
			{
				Name:  "backend",
				Tasks: []*toolchain.PlanTask{genTask},
			},
		},
		Tasks: map[toolchain.TaskKey]*toolchain.PlanTask{
			makeKey: makeTask,
			genKey:  genTask,
		},
	}

	result := toolchain.PlanToMermaid(plan)

	// Check for dependency edge
	if !strings.Contains(result, "morphir_elm_make --> morphir_elm_gen_Scala") {
		t.Errorf("expected dependency edge, got: %s", result)
	}
}

func TestPlanToMermaid_MultipleStages(t *testing.T) {
	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "build"},
		Stages: []toolchain.PlanStage{
			{Name: "stage1", Tasks: []*toolchain.PlanTask{}},
			{Name: "stage2", Tasks: []*toolchain.PlanTask{}},
			{Name: "stage3", Tasks: []*toolchain.PlanTask{}},
		},
		Tasks: map[toolchain.TaskKey]*toolchain.PlanTask{},
	}

	result := toolchain.PlanToMermaid(plan)

	if !strings.Contains(result, `subgraph stage_0["Stage: stage1"]`) {
		t.Errorf("expected stage_0, got: %s", result)
	}
	if !strings.Contains(result, `subgraph stage_1["Stage: stage2"]`) {
		t.Errorf("expected stage_1, got: %s", result)
	}
	if !strings.Contains(result, `subgraph stage_2["Stage: stage3"]`) {
		t.Errorf("expected stage_2, got: %s", result)
	}
}

func TestPlanToMermaid_SpecialCharacters(t *testing.T) {
	taskKey := toolchain.TaskKey{Toolchain: "my-tool", Task: "run<test>"}
	task := &toolchain.PlanTask{
		Key:       taskKey,
		Toolchain: "my-tool",
		Task:      "run<test>",
	}

	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "test"},
		Stages: []toolchain.PlanStage{
			{
				Name:  "test \"stage\"",
				Tasks: []*toolchain.PlanTask{task},
			},
		},
		Tasks: map[toolchain.TaskKey]*toolchain.PlanTask{
			taskKey: task,
		},
	}

	result := toolchain.PlanToMermaid(plan)

	// Check that special characters are escaped
	if !strings.Contains(result, "#quot;") {
		t.Errorf("expected escaped quotes, got: %s", result)
	}
	if !strings.Contains(result, "#lt;") || !strings.Contains(result, "#gt;") {
		t.Errorf("expected escaped angle brackets, got: %s", result)
	}
}

func TestPlanToMermaidWithOptions_ShowInputsAndOutputs(t *testing.T) {
	taskKey := toolchain.TaskKey{Toolchain: "morphir-elm", Task: "make"}
	task := &toolchain.PlanTask{
		Key:       taskKey,
		Toolchain: "morphir-elm",
		Task:      "make",
		Inputs: toolchain.InputSpec{
			Files: []string{"src/**/*.elm", "elm.json"},
		},
		Outputs: map[string]toolchain.OutputSpec{
			"ir": {Path: "morphir-ir.json", Type: "morphir-ir"},
		},
	}

	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "build"},
		Stages: []toolchain.PlanStage{
			{
				Name:  "frontend",
				Tasks: []*toolchain.PlanTask{task},
			},
		},
		Tasks: map[toolchain.TaskKey]*toolchain.PlanTask{
			taskKey: task,
		},
	}

	// Test showing both inputs and outputs
	opts := toolchain.MermaidOptions{ShowInputs: true, ShowOutputs: true}
	result := toolchain.PlanToMermaidWithOptions(plan, opts)

	// Check for inputs in label
	if !strings.Contains(result, "in:") {
		t.Errorf("expected inputs when ShowInputs=true, got: %s", result)
	}

	// Check for outputs in label
	if !strings.Contains(result, "out:") {
		t.Errorf("expected outputs when ShowOutputs=true, got: %s", result)
	}

	// Test showing only inputs
	optsInputsOnly := toolchain.MermaidOptions{ShowInputs: true, ShowOutputs: false}
	resultInputsOnly := toolchain.PlanToMermaidWithOptions(plan, optsInputsOnly)

	if !strings.Contains(resultInputsOnly, "in:") {
		t.Errorf("expected inputs when ShowInputs=true, got: %s", resultInputsOnly)
	}
	if strings.Contains(resultInputsOnly, "out:") {
		t.Errorf("expected no outputs when ShowOutputs=false, got: %s", resultInputsOnly)
	}

	// Test showing only outputs
	optsOutputsOnly := toolchain.MermaidOptions{ShowInputs: false, ShowOutputs: true}
	resultOutputsOnly := toolchain.PlanToMermaidWithOptions(plan, optsOutputsOnly)

	if strings.Contains(resultOutputsOnly, "in:") {
		t.Errorf("expected no inputs when ShowInputs=false, got: %s", resultOutputsOnly)
	}
	if !strings.Contains(resultOutputsOnly, "out:") {
		t.Errorf("expected outputs when ShowOutputs=true, got: %s", resultOutputsOnly)
	}
}

func TestPlanToMermaidWithOptions_TaskResults(t *testing.T) {
	successKey := toolchain.TaskKey{Toolchain: "tc", Task: "success"}
	failedKey := toolchain.TaskKey{Toolchain: "tc", Task: "failed"}

	successTask := &toolchain.PlanTask{Key: successKey, Toolchain: "tc", Task: "success"}
	failedTask := &toolchain.PlanTask{Key: failedKey, Toolchain: "tc", Task: "failed"}

	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "test"},
		Stages: []toolchain.PlanStage{
			{
				Name:  "test",
				Tasks: []*toolchain.PlanTask{successTask, failedTask},
			},
		},
		Tasks: map[toolchain.TaskKey]*toolchain.PlanTask{
			successKey: successTask,
			failedKey:  failedTask,
		},
	}

	opts := toolchain.MermaidOptions{
		TaskResults: map[toolchain.TaskKey]toolchain.TaskResult{
			successKey: {Metadata: toolchain.TaskMetadata{Success: true}},
			failedKey:  {Metadata: toolchain.TaskMetadata{Success: false}},
		},
	}

	result := toolchain.PlanToMermaidWithOptions(plan, opts)

	// Check for success styling
	if !strings.Contains(result, "classDef success") {
		t.Errorf("expected success class definition, got: %s", result)
	}

	// Check for failed styling
	if !strings.Contains(result, "classDef failed") {
		t.Errorf("expected failed class definition, got: %s", result)
	}
}

func TestPlanToMermaidWithOptions_SkippedTasks(t *testing.T) {
	executedKey := toolchain.TaskKey{Toolchain: "tc", Task: "executed"}
	skippedKey := toolchain.TaskKey{Toolchain: "tc", Task: "skipped"}

	executedTask := &toolchain.PlanTask{Key: executedKey, Toolchain: "tc", Task: "executed"}
	skippedTask := &toolchain.PlanTask{Key: skippedKey, Toolchain: "tc", Task: "skipped"}

	plan := toolchain.Plan{
		Workflow: toolchain.Workflow{Name: "test"},
		Stages: []toolchain.PlanStage{
			{
				Name:  "test",
				Tasks: []*toolchain.PlanTask{executedTask, skippedTask},
			},
		},
		Tasks: map[toolchain.TaskKey]*toolchain.PlanTask{
			executedKey: executedTask,
			skippedKey:  skippedTask,
		},
	}

	// Only provide result for executed task - skipped task has no result
	opts := toolchain.MermaidOptions{
		TaskResults: map[toolchain.TaskKey]toolchain.TaskResult{
			executedKey: {Metadata: toolchain.TaskMetadata{Success: true}},
		},
	}

	result := toolchain.PlanToMermaidWithOptions(plan, opts)

	// Check for skipped styling
	if !strings.Contains(result, "classDef skipped") {
		t.Errorf("expected skipped class definition, got: %s", result)
	}
}
