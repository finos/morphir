package toolchain

import (
	"testing"
	"time"

	"github.com/finos/morphir/pkg/vfs"
)

func createTestVFS() vfs.VFS {
	// Create an in-memory folder as the root
	root := vfs.NewMemFolder(
		vfs.MustVPath("/"),
		vfs.Meta{},
		vfs.Origin{MountName: "test"},
		[]vfs.Entry{},
	)

	// Create a mount with RW access
	mount := vfs.Mount{
		Name: "test",
		Mode: vfs.MountRW,
		Root: root,
	}

	// Create overlay VFS with the mount
	return vfs.NewOverlayVFS([]vfs.Mount{mount})
}

func TestRegistry_Register(t *testing.T) {
	registry := NewRegistry()

	tc := Toolchain{
		Name:    "test-toolchain",
		Version: "1.0.0",
		Type:    ToolchainTypeExternal,
		Acquire: AcquireConfig{
			Backend: "path",
		},
		Tasks: []TaskDef{
			{
				Name: "test-task",
				Exec: "echo",
				Args: []string{"hello"},
			},
		},
	}

	registry.Register(tc)

	// Verify toolchain was registered
	retrieved, ok := registry.GetToolchain("test-toolchain")
	if !ok {
		t.Fatal("toolchain not found after registration")
	}

	if retrieved.Name != "test-toolchain" {
		t.Errorf("expected toolchain name 'test-toolchain', got '%s'", retrieved.Name)
	}

	if retrieved.Version != "1.0.0" {
		t.Errorf("expected version '1.0.0', got '%s'", retrieved.Version)
	}

	if len(retrieved.Tasks) != 1 {
		t.Errorf("expected 1 task, got %d", len(retrieved.Tasks))
	}
}

func TestRegistry_RegisterTarget(t *testing.T) {
	registry := NewRegistry()

	target := Target{
		Name:        "make",
		Description: "Compile sources to IR",
		Produces:    []string{"morphir-ir"},
	}

	registry.RegisterTarget(target)

	// Verify target was registered
	retrieved, ok := registry.GetTarget("make")
	if !ok {
		t.Fatal("target not found after registration")
	}

	if retrieved.Name != "make" {
		t.Errorf("expected target name 'make', got '%s'", retrieved.Name)
	}

	if len(retrieved.Produces) != 1 || retrieved.Produces[0] != "morphir-ir" {
		t.Errorf("expected produces ['morphir-ir'], got %v", retrieved.Produces)
	}
}

func TestRegistry_ListToolchains(t *testing.T) {
	registry := NewRegistry()

	tc1 := Toolchain{Name: "toolchain-a", Type: ToolchainTypeExternal}
	tc2 := Toolchain{Name: "toolchain-b", Type: ToolchainTypeExternal}

	registry.Register(tc1)
	registry.Register(tc2)

	names := registry.ListToolchains()
	if len(names) != 2 {
		t.Errorf("expected 2 toolchains, got %d", len(names))
	}

	// Check that both names are present
	found := make(map[string]bool)
	for _, name := range names {
		found[name] = true
	}

	if !found["toolchain-a"] || !found["toolchain-b"] {
		t.Errorf("expected toolchains 'toolchain-a' and 'toolchain-b', got %v", names)
	}
}

func TestRegistry_ListTargets(t *testing.T) {
	registry := NewRegistry()

	t1 := Target{Name: "make"}
	t2 := Target{Name: "gen"}

	registry.RegisterTarget(t1)
	registry.RegisterTarget(t2)

	names := registry.ListTargets()
	if len(names) != 2 {
		t.Errorf("expected 2 targets, got %d", len(names))
	}

	// Check that both names are present
	found := make(map[string]bool)
	for _, name := range names {
		found[name] = true
	}

	if !found["make"] || !found["gen"] {
		t.Errorf("expected targets 'make' and 'gen', got %v", names)
	}
}

func TestOutputDirStructure_TaskOutputDir(t *testing.T) {
	vfsInstance := createTestVFS()
	root := vfs.MustVPath(".morphir/out")

	outputDir := NewOutputDirStructure(root, vfsInstance)

	taskDir, err := outputDir.TaskOutputDir("test-toolchain", "test-task")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expected := ".morphir/out/test-toolchain/test-task"

	if taskDir.String() != expected {
		t.Errorf("expected task dir '%s', got '%s'", expected, taskDir.String())
	}
}

func TestOutputDirStructure_MetaPath(t *testing.T) {
	vfsInstance := createTestVFS()
	root := vfs.MustVPath(".morphir/out")

	outputDir := NewOutputDirStructure(root, vfsInstance)

	metaPath, err := outputDir.MetaPath("test-toolchain", "test-task")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expected := ".morphir/out/test-toolchain/test-task/meta.json"

	if metaPath.String() != expected {
		t.Errorf("expected meta path '%s', got '%s'", expected, metaPath.String())
	}
}

func TestOutputDirStructure_DiagnosticsPath(t *testing.T) {
	vfsInstance := createTestVFS()
	root := vfs.MustVPath(".morphir/out")

	outputDir := NewOutputDirStructure(root, vfsInstance)

	diagPath, err := outputDir.DiagnosticsPath("test-toolchain", "test-task")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expected := ".morphir/out/test-toolchain/test-task/diagnostics.jsonl"

	if diagPath.String() != expected {
		t.Errorf("expected diagnostics path '%s', got '%s'", expected, diagPath.String())
	}
}

func TestOutputDirStructure_OutputPath(t *testing.T) {
	vfsInstance := createTestVFS()
	root := vfs.MustVPath(".morphir/out")

	outputDir := NewOutputDirStructure(root, vfsInstance)

	outputPath, err := outputDir.OutputPath("test-toolchain", "test-task", "output.json")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expected := ".morphir/out/test-toolchain/test-task/output.json"

	if outputPath.String() != expected {
		t.Errorf("expected output path '%s', got '%s'", expected, outputPath.String())
	}
}

func TestTaskMetadata_Fields(t *testing.T) {
	startTime := time.Now()
	endTime := startTime.Add(5 * time.Second)

	metadata := TaskMetadata{
		ToolchainName: "test-toolchain",
		TaskName:      "test-task",
		InputsHash:    "abc123",
		StartTime:     startTime,
		EndTime:       endTime,
		Duration:      5 * time.Second,
		ExitCode:      0,
		Success:       true,
	}

	if metadata.ToolchainName != "test-toolchain" {
		t.Errorf("expected toolchain name 'test-toolchain', got '%s'", metadata.ToolchainName)
	}

	if metadata.TaskName != "test-task" {
		t.Errorf("expected task name 'test-task', got '%s'", metadata.TaskName)
	}

	if metadata.Duration != 5*time.Second {
		t.Errorf("expected duration 5s, got %v", metadata.Duration)
	}

	if !metadata.Success {
		t.Error("expected success to be true")
	}
}

func TestWorkflowStage_Fields(t *testing.T) {
	stage := WorkflowStage{
		Name:      "compile",
		Targets:   []string{"make"},
		Parallel:  false,
		Condition: "",
	}

	if stage.Name != "compile" {
		t.Errorf("expected stage name 'compile', got '%s'", stage.Name)
	}

	if len(stage.Targets) != 1 || stage.Targets[0] != "make" {
		t.Errorf("expected targets ['make'], got %v", stage.Targets)
	}

	if stage.Parallel {
		t.Error("expected parallel to be false")
	}
}

func TestWorkflow_Fields(t *testing.T) {
	workflow := Workflow{
		Name:        "build",
		Description: "Standard build workflow",
		Extends:     "",
		Stages: []WorkflowStage{
			{
				Name:    "frontend",
				Targets: []string{"make"},
			},
			{
				Name:    "backend",
				Targets: []string{"gen:scala"},
			},
		},
	}

	if workflow.Name != "build" {
		t.Errorf("expected workflow name 'build', got '%s'", workflow.Name)
	}

	if len(workflow.Stages) != 2 {
		t.Errorf("expected 2 stages, got %d", len(workflow.Stages))
	}

	if workflow.Stages[0].Name != "frontend" {
		t.Errorf("expected first stage name 'frontend', got '%s'", workflow.Stages[0].Name)
	}
}
