package steps

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/cucumber/godog"
)

// GolangTestContext holds state for golang CLI BDD tests
type GolangTestContext struct {
	tempDir      string
	irFilePath   string
	outputDir    string
	modulePath   string
	cmdOutput    bytes.Buffer
	cmdError     bytes.Buffer
	cmdExitCode  int
	useWorkspace bool
	useJSON      bool
	useVerbose   bool
	jsonOutput   map[string]interface{}
}

// NewGolangTestContext creates a new test context
func NewGolangTestContext() *GolangTestContext {
	return &GolangTestContext{
		modulePath: "example.com/generated",
	}
}

// Reset clears the test context state
func (g *GolangTestContext) Reset() error {
	// Clean up temp directory if exists
	if g.tempDir != "" {
		os.RemoveAll(g.tempDir)
	}

	// Create new temp directory
	tempDir, err := os.MkdirTemp("", "golang-bdd-*")
	if err != nil {
		return err
	}

	g.tempDir = tempDir
	g.irFilePath = ""
	g.outputDir = filepath.Join(tempDir, "output")
	g.modulePath = "example.com/generated"
	g.cmdOutput.Reset()
	g.cmdError.Reset()
	g.cmdExitCode = 0
	g.useWorkspace = false
	g.useJSON = false
	g.useVerbose = false
	g.jsonOutput = nil

	return os.MkdirAll(g.outputDir, 0755)
}

// Cleanup removes temporary files
func (g *GolangTestContext) Cleanup() error {
	if g.tempDir != "" {
		return os.RemoveAll(g.tempDir)
	}
	return nil
}

// RegisterGolangSteps registers all golang CLI step definitions
func RegisterGolangSteps(sc *godog.ScenarioContext) {
	g := NewGolangTestContext()

	// Setup/teardown
	sc.Before(func(ctx context.Context, sc *godog.Scenario) (context.Context, error) {
		if err := g.Reset(); err != nil {
			return ctx, err
		}
		return ctx, nil
	})

	sc.After(func(ctx context.Context, sc *godog.Scenario, err error) (context.Context, error) {
		if cleanupErr := g.Cleanup(); cleanupErr != nil && err == nil {
			err = cleanupErr
		}
		return ctx, err
	})

	// Given steps
	sc.Step(`^a minimal Morphir IR file$`, g.aMinimalMorphirIRFile)

	// When steps - command execution variations
	sc.Step(`^I run morphir golang gen without --output flag$`, g.runWithoutOutputFlag)
	sc.Step(`^I run morphir golang gen without --module-path flag$`, g.runWithoutModulePathFlag)
	sc.Step(`^I run morphir golang gen without an IR file$`, g.runWithoutIRFile)
	sc.Step(`^I run morphir golang gen with --json flag$`, g.runWithJSONFlag)
	sc.Step(`^I run morphir golang gen with --workspace flag$`, g.runWithWorkspaceFlag)
	sc.Step(`^I run morphir golang gen without --workspace flag$`, g.runWithoutWorkspaceFlag)
	sc.Step(`^I run morphir golang gen with module path "([^"]*)"$`, g.runWithModulePath)
	sc.Step(`^I run morphir golang gen$`, g.runGolangGen)
	sc.Step(`^I run morphir golang gen with --verbose flag$`, g.runWithVerboseFlag)

	// Then steps - command result checks
	sc.Step(`^the command should fail$`, g.commandShouldFail)
	sc.Step(`^the command should succeed$`, g.commandShouldSucceed)
	sc.Step(`^the error should mention "([^"]*)"$`, g.errorShouldMention)
	sc.Step(`^the output should be valid JSON$`, g.outputShouldBeValidJSON)
	sc.Step(`^the JSON output should have "([^"]*)" field$`, g.jsonOutputShouldHaveField)
	sc.Step(`^the JSON output should have "([^"]*)" equal to ([^$]+)$`, g.jsonOutputShouldHaveValueEqual)
	sc.Step(`^the output directory should contain "([^"]*)"$`, g.outputDirShouldContain)
	sc.Step(`^the output directory should not contain "([^"]*)"$`, g.outputDirShouldNotContain)
	sc.Step(`^the output directory should contain a "([^"]*)" file$`, g.outputDirShouldContainFileWithExtension)
	sc.Step(`^the go\.mod should have module path "([^"]*)"$`, g.goModShouldHaveModulePath)
	sc.Step(`^the output should list generated files$`, g.outputShouldListGeneratedFiles)
}

// Step implementations

func (g *GolangTestContext) aMinimalMorphirIRFile() error {
	// Create a minimal Morphir IR JSON file
	minimalIR := `{
		"formatVersion": 3,
		"distribution": [
			"Library",
			[["example"]],
			{},
			{}
		]
	}`

	g.irFilePath = filepath.Join(g.tempDir, "morphir-ir.json")
	return os.WriteFile(g.irFilePath, []byte(minimalIR), 0644)
}

func (g *GolangTestContext) runMorphirCmd(args ...string) error {
	cmd := exec.Command("morphir", args...)
	cmd.Stdout = &g.cmdOutput
	cmd.Stderr = &g.cmdError

	err := cmd.Run()
	if exitErr, ok := err.(*exec.ExitError); ok {
		g.cmdExitCode = exitErr.ExitCode()
	} else if err != nil {
		g.cmdExitCode = 1
	} else {
		g.cmdExitCode = 0
	}

	return nil
}

func (g *GolangTestContext) runWithoutOutputFlag() error {
	return g.runMorphirCmd("golang", "gen", g.irFilePath, "-m", g.modulePath)
}

func (g *GolangTestContext) runWithoutModulePathFlag() error {
	return g.runMorphirCmd("golang", "gen", g.irFilePath, "-o", g.outputDir)
}

func (g *GolangTestContext) runWithoutIRFile() error {
	return g.runMorphirCmd("golang", "gen", "-o", g.outputDir, "-m", g.modulePath)
}

func (g *GolangTestContext) runWithJSONFlag() error {
	g.useJSON = true
	err := g.runMorphirCmd("golang", "gen", g.irFilePath, "-o", g.outputDir, "-m", g.modulePath, "--json")
	if err == nil && g.cmdExitCode == 0 {
		// Parse JSON output
		var result map[string]interface{}
		if jsonErr := json.Unmarshal(g.cmdOutput.Bytes(), &result); jsonErr == nil {
			g.jsonOutput = result
		}
	}
	return err
}

func (g *GolangTestContext) runWithWorkspaceFlag() error {
	g.useWorkspace = true
	return g.runMorphirCmd("golang", "gen", g.irFilePath, "-o", g.outputDir, "-m", g.modulePath, "--workspace")
}

func (g *GolangTestContext) runWithoutWorkspaceFlag() error {
	return g.runMorphirCmd("golang", "gen", g.irFilePath, "-o", g.outputDir, "-m", g.modulePath)
}

func (g *GolangTestContext) runWithModulePath(modulePath string) error {
	g.modulePath = modulePath
	return g.runMorphirCmd("golang", "gen", g.irFilePath, "-o", g.outputDir, "-m", modulePath)
}

func (g *GolangTestContext) runGolangGen() error {
	return g.runMorphirCmd("golang", "gen", g.irFilePath, "-o", g.outputDir, "-m", g.modulePath)
}

func (g *GolangTestContext) runWithVerboseFlag() error {
	g.useVerbose = true
	return g.runMorphirCmd("golang", "gen", g.irFilePath, "-o", g.outputDir, "-m", g.modulePath, "--verbose")
}

func (g *GolangTestContext) commandShouldFail() error {
	if g.cmdExitCode == 0 {
		return fmt.Errorf("expected command to fail, but it succeeded")
	}
	return nil
}

func (g *GolangTestContext) commandShouldSucceed() error {
	if g.cmdExitCode != 0 {
		return fmt.Errorf("expected command to succeed, but it failed with exit code %d: %s",
			g.cmdExitCode, g.cmdError.String())
	}
	return nil
}

func (g *GolangTestContext) errorShouldMention(keyword string) error {
	combined := g.cmdOutput.String() + g.cmdError.String()
	if !strings.Contains(strings.ToLower(combined), strings.ToLower(keyword)) {
		return fmt.Errorf("expected output to mention %q, got: %s", keyword, combined)
	}
	return nil
}

func (g *GolangTestContext) outputShouldBeValidJSON() error {
	var result interface{}
	if err := json.Unmarshal(g.cmdOutput.Bytes(), &result); err != nil {
		return fmt.Errorf("output is not valid JSON: %w", err)
	}
	return nil
}

func (g *GolangTestContext) jsonOutputShouldHaveField(field string) error {
	if g.jsonOutput == nil {
		// Try to parse output as JSON
		var result map[string]interface{}
		if err := json.Unmarshal(g.cmdOutput.Bytes(), &result); err != nil {
			return fmt.Errorf("output is not valid JSON: %w", err)
		}
		g.jsonOutput = result
	}

	if _, ok := g.jsonOutput[field]; !ok {
		return fmt.Errorf("JSON output missing field %q, got: %v", field, g.jsonOutput)
	}
	return nil
}

func (g *GolangTestContext) jsonOutputShouldHaveValueEqual(field, value string) error {
	if g.jsonOutput == nil {
		return fmt.Errorf("no JSON output available")
	}

	actual, ok := g.jsonOutput[field]
	if !ok {
		return fmt.Errorf("JSON output missing field %q", field)
	}

	// Compare as strings for simplicity
	actualStr := fmt.Sprintf("%v", actual)
	if actualStr != value {
		return fmt.Errorf("expected %q to be %q, got %q", field, value, actualStr)
	}
	return nil
}

func (g *GolangTestContext) outputDirShouldContain(filename string) error {
	path := filepath.Join(g.outputDir, filename)
	if _, err := os.Stat(path); os.IsNotExist(err) {
		// List directory contents for debugging
		entries, _ := os.ReadDir(g.outputDir)
		var names []string
		for _, e := range entries {
			names = append(names, e.Name())
		}
		return fmt.Errorf("expected output directory to contain %q, found: %v", filename, names)
	}
	return nil
}

func (g *GolangTestContext) outputDirShouldNotContain(filename string) error {
	path := filepath.Join(g.outputDir, filename)
	if _, err := os.Stat(path); err == nil {
		return fmt.Errorf("expected output directory NOT to contain %q, but it exists", filename)
	}
	return nil
}

func (g *GolangTestContext) outputDirShouldContainFileWithExtension(extension string) error {
	// Check recursively
	return g.findFileWithExtension(g.outputDir, extension)
}

func (g *GolangTestContext) findFileWithExtension(dir, extension string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}

	for _, entry := range entries {
		if entry.IsDir() {
			if err := g.findFileWithExtension(filepath.Join(dir, entry.Name()), extension); err == nil {
				return nil
			}
		} else if strings.HasSuffix(entry.Name(), extension) {
			return nil
		}
	}

	return fmt.Errorf("no file with extension %q found in %s", extension, dir)
}

func (g *GolangTestContext) goModShouldHaveModulePath(modulePath string) error {
	goModPath := filepath.Join(g.outputDir, "go.mod")
	content, err := os.ReadFile(goModPath)
	if err != nil {
		return fmt.Errorf("failed to read go.mod: %w", err)
	}

	expectedLine := fmt.Sprintf("module %s", modulePath)
	if !strings.Contains(string(content), expectedLine) {
		return fmt.Errorf("go.mod does not contain module path %q, content: %s", modulePath, string(content))
	}
	return nil
}

func (g *GolangTestContext) outputShouldListGeneratedFiles() error {
	output := g.cmdOutput.String()
	if !strings.Contains(output, "Generated files") && !strings.Contains(output, "generated") {
		return fmt.Errorf("expected output to list generated files, got: %s", output)
	}
	return nil
}
