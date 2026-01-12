package toolchain

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
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
	os.Remove(irPath)
	os.Remove(hashesPath)

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
		os.Remove(irPath)
		os.Remove(hashesPath)
		// Clean up elm-stuff if created
		elmStuffPath := filepath.Join(projectPath, "elm-stuff")
		os.RemoveAll(elmStuffPath)
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
