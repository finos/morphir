package toolchain

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// TestIntegration_MorphirElmMake tests the full morphir-elm toolchain integration
// by directly invoking npx morphir-elm make on the example project.
// This test requires Node.js/npx to be installed (provided by mise).
func TestIntegration_MorphirElmMake(t *testing.T) {
	// Skip if running short tests
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	// Check if npx is available
	npxPath, err := exec.LookPath("npx")
	if err != nil {
		t.Skip("npx not installed - skipping integration test (run with mise to ensure Node.js is available)")
	}
	t.Logf("Found npx at: %s", npxPath)

	// Find the morphir-elm-compat example project
	projectPath := findExampleProject(t, "morphir-elm-compat")
	t.Logf("Using example project at: %s", projectPath)

	// Verify required files exist
	requiredFiles := []string{"elm.json", "morphir.json", "src/ElmCompat/Main.elm", "src/ElmCompat/Api.elm"}
	for _, f := range requiredFiles {
		path := filepath.Join(projectPath, f)
		if _, err := os.Stat(path); os.IsNotExist(err) {
			t.Fatalf("required file not found: %s", path)
		}
	}

	// Clean up any previous build artifacts
	irPath := filepath.Join(projectPath, "morphir-ir.json")
	hashesPath := filepath.Join(projectPath, "morphir-hashes.json")
	_ = os.Remove(irPath)
	_ = os.Remove(hashesPath)

	// Execute morphir-elm make directly using npx
	t.Log("Executing npx morphir-elm make...")
	cmd := exec.Command("npx", "-y", "morphir-elm", "make")
	cmd.Dir = projectPath
	cmd.Env = append(os.Environ(), "NODE_OPTIONS=--max-old-space-size=4096")

	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Logf("Command output:\n%s", string(output))
		t.Fatalf("morphir-elm make failed: %v", err)
	}

	t.Logf("morphir-elm make output:\n%s", string(output))

	// Verify morphir-ir.json was created
	if _, err := os.Stat(irPath); os.IsNotExist(err) {
		t.Fatal("morphir-ir.json was not created")
	}

	// Read and validate the IR
	irContent, err := os.ReadFile(irPath)
	if err != nil {
		t.Fatalf("failed to read morphir-ir.json: %v", err)
	}

	var ir MorphirIR
	if err := json.Unmarshal(irContent, &ir); err != nil {
		t.Fatalf("failed to parse morphir-ir.json: %v", err)
	}

	// Validate IR structure
	t.Run("ValidateIRStructure", func(t *testing.T) {
		if ir.FormatVersion != 3 {
			t.Errorf("expected format version 3, got %d", ir.FormatVersion)
		}

		if len(ir.Distribution) < 4 {
			t.Fatalf("invalid distribution structure, expected at least 4 elements")
		}

		distType, ok := ir.Distribution[0].(string)
		if !ok || distType != "Library" {
			t.Errorf("expected distribution type 'Library', got %v", ir.Distribution[0])
		}
	})

	t.Run("ValidateModules", func(t *testing.T) {
		modules := extractModules(t, ir)
		if len(modules) != 2 {
			t.Errorf("expected 2 modules, got %d", len(modules))
		}

		// Check for expected modules
		moduleNames := make(map[string]bool)
		for _, m := range modules {
			moduleNames[m] = true
		}

		expectedModules := []string{"main", "api"}
		for _, expected := range expectedModules {
			if !moduleNames[expected] {
				t.Errorf("expected module %q not found in IR", expected)
			}
		}
	})

	// Clean up generated files
	t.Cleanup(func() {
		_ = os.Remove(irPath)
		_ = os.Remove(hashesPath)
		// Clean up elm-stuff if created
		elmStuffPath := filepath.Join(projectPath, "elm-stuff")
		_ = os.RemoveAll(elmStuffPath)
	})
}

// MorphirIR represents the top-level structure of a Morphir IR file
type MorphirIR struct {
	FormatVersion int           `json:"formatVersion"`
	Distribution  []interface{} `json:"distribution"`
}

// findExampleProject locates an example project relative to the test file
func findExampleProject(t *testing.T, name string) string {
	t.Helper()

	// Get the directory of this test file
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("failed to get test file location")
	}

	// Navigate from pkg/toolchain to examples/
	pkgDir := filepath.Dir(filename)
	repoRoot := filepath.Join(pkgDir, "..", "..")
	examplePath := filepath.Join(repoRoot, "examples", name)

	absPath, err := filepath.Abs(examplePath)
	if err != nil {
		t.Fatalf("failed to resolve example path: %v", err)
	}

	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		t.Fatalf("example project not found: %s", absPath)
	}

	return absPath
}

// TestIntegration_WorkflowExecution tests workflow execution with the built-in morphir-elm toolchain.
// This verifies that running a build workflow properly invokes morphir-elm tasks.
func TestIntegration_WorkflowExecution(t *testing.T) {
	// Skip if running short tests
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	// Check if npx is available
	if _, err := exec.LookPath("npx"); err != nil {
		t.Skip("npx not installed - skipping integration test")
	}

	// Find the morphir-elm-compat example project
	projectPath := findExampleProject(t, "morphir-elm-compat")
	t.Logf("Using example project at: %s", projectPath)

	// Clean up any previous build artifacts
	irPath := filepath.Join(projectPath, "morphir-ir.json")
	hashesPath := filepath.Join(projectPath, "morphir-hashes.json")
	morphirOutPath := filepath.Join(projectPath, ".morphir", "out")
	_ = os.Remove(irPath)
	_ = os.Remove(hashesPath)
	_ = os.RemoveAll(morphirOutPath)

	// Create test infrastructure with OS-backed VFS
	mount := vfs.NewOSMount("workspace", vfs.MountRW, projectPath, vfs.MustVPath("/"))
	vfsInstance := vfs.NewOverlayVFS([]vfs.Mount{mount})
	ctx := pipeline.NewContext(projectPath, 3, pipeline.ModeDefault, vfsInstance)
	outputDir := NewOutputDirStructure(vfs.MustVPath("/.morphir/out"), vfsInstance)
	registry := NewRegistry()

	// Register the morphir-elm toolchain (inline to avoid import cycle)
	// This mirrors the definition in pkg/bindings/morphir-elm/toolchain
	registry.Register(Toolchain{
		Name:        "morphir-elm",
		Version:     "2.100.0",
		Description: "Morphir-elm toolchain for Elm-based IR generation",
		Type:        ToolchainTypeExternal,
		Acquire: AcquireConfig{
			Backend: "npx",
			Package: "morphir-elm",
			Version: "2.100.0",
		},
		Timeout: 10 * time.Minute,
		Env: map[string]string{
			"NODE_OPTIONS": "--max-old-space-size=4096",
		},
		Tasks: []TaskDef{
			{
				Name:        "make",
				Description: "Compile Elm sources to Morphir IR",
				Args:        []string{"make"},
				Inputs: InputSpec{
					Files: []string{"elm.json", "src/**/*.elm", "morphir.json"},
				},
				Outputs: map[string]OutputSpec{
					"ir": {Path: "morphir-ir.json", Type: "morphir-ir"},
				},
				Fulfills: []string{"make"},
				Timeout:  10 * time.Minute,
			},
		},
	})

	// Verify toolchain was registered
	tc, ok := registry.GetToolchain("morphir-elm")
	if !ok {
		t.Fatal("morphir-elm toolchain was not registered")
	}
	t.Logf("Registered morphir-elm toolchain v%s", tc.Version)

	// Create executor and runner
	executor := NewExecutor(registry, outputDir, ctx)
	runner := NewWorkflowRunner(executor, outputDir)

	// Create a simple build workflow
	makeTask := &PlanTask{
		Key:       TaskKey{Toolchain: "morphir-elm", Task: "make"},
		Toolchain: "morphir-elm",
		Task:      "make",
	}

	plan := Plan{
		Workflow: Workflow{
			Name:        "build",
			Description: "Build workflow for integration test",
		},
		Stages: []PlanStage{
			{
				Name:     "compile",
				Parallel: false,
				Tasks:    []*PlanTask{makeTask},
			},
		},
		Tasks: map[TaskKey]*PlanTask{
			makeTask.Key: makeTask,
		},
	}

	// Track progress events
	var events []ProgressEvent
	opts := DefaultRunOptions()
	opts.Progress = func(event ProgressEvent) {
		events = append(events, event)
		t.Logf("Progress: %s - %s", event.Type, event.Message)
	}

	// Execute the workflow
	t.Log("Executing build workflow...")
	result := runner.Run(plan, opts)

	// Verify workflow execution
	t.Run("WorkflowSucceeds", func(t *testing.T) {
		if !result.Success {
			t.Errorf("workflow failed: %v", result.Error)
			// Log task results for debugging
			for key, taskResult := range result.TaskResults {
				t.Logf("Task %s: success=%v, error=%v", key.String(), taskResult.Metadata.Success, taskResult.Error)
			}
		}
	})

	t.Run("MorphirElmTaskExecuted", func(t *testing.T) {
		taskResult, ok := result.TaskResults[makeTask.Key]
		if !ok {
			t.Fatal("morphir-elm/make task result not found")
		}
		if !taskResult.Metadata.Success {
			t.Errorf("morphir-elm/make task failed: %v", taskResult.Error)
		}
		if taskResult.Metadata.ToolchainName != "morphir-elm" {
			t.Errorf("expected toolchain name 'morphir-elm', got %s", taskResult.Metadata.ToolchainName)
		}
		if taskResult.Metadata.TaskName != "make" {
			t.Errorf("expected task name 'make', got %s", taskResult.Metadata.TaskName)
		}
	})

	t.Run("ProgressEventsReceived", func(t *testing.T) {
		// Should have workflow started, stage started, task started, task completed, stage completed, workflow completed
		expectedTypes := []ProgressEventType{
			ProgressWorkflowStarted,
			ProgressStageStarted,
			ProgressTaskStarted,
			ProgressTaskCompleted,
			ProgressStageCompleted,
			ProgressWorkflowCompleted,
		}

		if len(events) < len(expectedTypes) {
			t.Errorf("expected at least %d events, got %d", len(expectedTypes), len(events))
		}

		for i, expected := range expectedTypes {
			if i >= len(events) {
				break
			}
			if events[i].Type != expected {
				t.Errorf("event %d: expected type %s, got %s", i, expected, events[i].Type)
			}
		}
	})

	t.Run("IROutputCreated", func(t *testing.T) {
		// Verify morphir-ir.json was created (morphir-elm writes to project root)
		if _, err := os.Stat(irPath); os.IsNotExist(err) {
			t.Error("morphir-ir.json was not created")
		}

		// Read and validate the IR
		irContent, err := os.ReadFile(irPath)
		if err != nil {
			t.Fatalf("failed to read morphir-ir.json: %v", err)
		}

		var ir MorphirIR
		if err := json.Unmarshal(irContent, &ir); err != nil {
			t.Fatalf("failed to parse morphir-ir.json: %v", err)
		}

		if ir.FormatVersion != 3 {
			t.Errorf("expected format version 3, got %d", ir.FormatVersion)
		}
	})

	// Clean up generated files
	t.Cleanup(func() {
		_ = os.Remove(irPath)
		_ = os.Remove(hashesPath)
		_ = os.RemoveAll(morphirOutPath)
		elmStuffPath := filepath.Join(projectPath, "elm-stuff")
		_ = os.RemoveAll(elmStuffPath)
	})
}

// extractModules extracts module names from the IR distribution
func extractModules(t *testing.T, ir MorphirIR) []string {
	t.Helper()

	if len(ir.Distribution) < 4 {
		t.Fatal("invalid distribution structure")
	}

	// Distribution[3] is the package definition containing modules
	pkgDef, ok := ir.Distribution[3].(map[string]interface{})
	if !ok {
		t.Fatal("failed to parse package definition")
	}

	modulesRaw, ok := pkgDef["modules"].([]interface{})
	if !ok {
		t.Fatal("failed to parse modules array")
	}

	var moduleNames []string
	for _, m := range modulesRaw {
		moduleArr, ok := m.([]interface{})
		if !ok || len(moduleArr) < 1 {
			continue
		}

		// Module name is the first element, which is an array of path segments
		nameArr, ok := moduleArr[0].([]interface{})
		if !ok || len(nameArr) < 1 {
			continue
		}

		// Each segment is itself an array of strings
		var nameParts []string
		for _, seg := range nameArr {
			segArr, ok := seg.([]interface{})
			if !ok {
				continue
			}
			for _, part := range segArr {
				if s, ok := part.(string); ok {
					nameParts = append(nameParts, s)
				}
			}
		}

		if len(nameParts) > 0 {
			moduleNames = append(moduleNames, nameParts[len(nameParts)-1])
		}
	}

	return moduleNames
}
