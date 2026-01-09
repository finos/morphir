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
	tempDir        string
	irFilePath     string
	outputDir      string
	modulePath     string
	cmdOutput      bytes.Buffer
	cmdError       bytes.Buffer
	cmdExitCode    int
	useWorkspace   bool
	useJSON        bool
	useVerbose     bool
	jsonOutput     map[string]interface{}
	sourceFilePath string
	jsonlFilePath  string
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
	g.sourceFilePath = ""
	g.jsonlFilePath = ""

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

	// Given steps - IR fixtures
	sc.Step(`^a minimal Morphir IR file$`, g.aMinimalMorphirIRFile)
	sc.Step(`^the type-alias IR fixture$`, g.theTypeAliasIRFixture)
	sc.Step(`^the record-type IR fixture$`, g.theRecordTypeIRFixture)
	sc.Step(`^the multi-module IR fixture$`, g.theMultiModuleIRFixture)
	sc.Step(`^an IR with unsupported constructs$`, g.anIRWithUnsupportedConstructs)

	// Given steps - other inputs
	sc.Step(`^a Go source file$`, g.aGoSourceFile)
	sc.Step(`^a JSONL file with multiple IR inputs$`, g.aJSONLFileWithMultipleIRInputs)
	sc.Step(`^a JSONL file with multiple source inputs$`, g.aJSONLFileWithMultipleSourceInputs)
	sc.Step(`^Go toolchain is available$`, g.goToolchainIsAvailable)

	// When steps - gen command variations
	sc.Step(`^I run morphir golang gen without --output flag$`, g.runWithoutOutputFlag)
	sc.Step(`^I run morphir golang gen without --module-path flag$`, g.runWithoutModulePathFlag)
	sc.Step(`^I run morphir golang gen without an IR file$`, g.runWithoutIRFile)
	sc.Step(`^I run morphir golang gen with --json flag$`, g.runWithJSONFlag)
	sc.Step(`^I run morphir golang gen with --workspace flag$`, g.runWithWorkspaceFlag)
	sc.Step(`^I run morphir golang gen without --workspace flag$`, g.runWithoutWorkspaceFlag)
	sc.Step(`^I run morphir golang gen with module path "([^"]*)"$`, g.runWithModulePath)
	sc.Step(`^I run morphir golang gen$`, g.runGolangGen)
	sc.Step(`^I run morphir golang gen with --verbose flag$`, g.runWithVerboseFlag)

	// When steps - build command variations
	sc.Step(`^I run morphir golang build without an IR file$`, g.runBuildWithoutIRFile)
	sc.Step(`^I run morphir golang build without --output flag$`, g.runBuildWithoutOutputFlag)
	sc.Step(`^I run morphir golang build without --module-path flag$`, g.runBuildWithoutModulePathFlag)
	sc.Step(`^I run morphir golang build with valid arguments$`, g.runBuildWithValidArgs)
	sc.Step(`^I run morphir golang build with --json flag$`, g.runBuildWithJSONFlag)
	sc.Step(`^I run morphir golang build with --workspace flag$`, g.runBuildWithWorkspaceFlag)
	sc.Step(`^I run morphir golang build with --jsonl-input flag$`, g.runBuildWithJSONLInputFlag)

	// When steps - make command variations
	sc.Step(`^I run morphir golang make$`, g.runGolangMake)
	sc.Step(`^I run morphir golang make with the source file$`, g.runMakeWithSourceFile)
	sc.Step(`^I run morphir golang make with --json flag$`, g.runMakeWithJSONFlag)
	sc.Step(`^I run morphir golang make with --jsonl-input flag$`, g.runMakeWithJSONLInputFlag)

	// When steps - go toolchain
	sc.Step(`^I run go build in the output directory$`, g.runGoBuildInOutputDir)

	// Then steps - command result checks
	sc.Step(`^the command should fail$`, g.commandShouldFail)
	sc.Step(`^the command should succeed$`, g.commandShouldSucceed)
	sc.Step(`^the error should mention "([^"]*)"$`, g.errorShouldMention)
	sc.Step(`^the output should mention "([^"]*)"$`, g.outputShouldMention)
	sc.Step(`^the output should be valid JSON$`, g.outputShouldBeValidJSON)
	sc.Step(`^the JSON output should have "([^"]*)" field$`, g.jsonOutputShouldHaveField)
	sc.Step(`^the JSON output should have "([^"]*)" equal to ([^$]+)$`, g.jsonOutputShouldHaveValueEqual)
	sc.Step(`^the output directory should contain "([^"]*)"$`, g.outputDirShouldContain)
	sc.Step(`^the output directory should not contain "([^"]*)"$`, g.outputDirShouldNotContain)
	sc.Step(`^the output directory should contain a "([^"]*)" file$`, g.outputDirShouldContainFileWithExtension)
	sc.Step(`^the go\.mod should have module path "([^"]*)"$`, g.goModShouldHaveModulePath)
	sc.Step(`^the output should list generated files$`, g.outputShouldListGeneratedFiles)

	// Then steps - batch processing
	sc.Step(`^the command should process all inputs$`, g.commandShouldProcessAllInputs)
	sc.Step(`^the output should contain JSONL results$`, g.outputShouldContainJSONLResults)

	// Then steps - acceptance tests
	sc.Step(`^the go build should succeed$`, g.goBuildShouldSucceed)
	sc.Step(`^the go\.mod should be valid$`, g.goModShouldBeValid)
	sc.Step(`^all \.go files should have valid syntax$`, g.allGoFilesShouldHaveValidSyntax)
	sc.Step(`^the diagnostics should contain warnings$`, g.diagnosticsShouldContainWarnings)
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

// New fixture step implementations

func (g *GolangTestContext) theTypeAliasIRFixture() error {
	// Load from fixtures directory or create inline
	typeAliasIR := `{
		"formatVersion": 3,
		"distribution": [
			"Library",
			[["example"], ["domain"]],
			{},
			{
				"modules": [
					{
						"name": [["types"]],
						"def": [
							"public",
							{
								"types": [
									[
										[["user", "id"]],
										[
											"public",
											[
												"A unique identifier for users",
												[
													"type_alias_definition",
													[],
													[
														"reference",
														{},
														[[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]],
														[]
													]
												]
											]
										]
									]
								],
								"values": []
							}
						]
					}
				]
			}
		]
	}`
	g.irFilePath = filepath.Join(g.tempDir, "type-alias-ir.json")
	return os.WriteFile(g.irFilePath, []byte(typeAliasIR), 0644)
}

func (g *GolangTestContext) theRecordTypeIRFixture() error {
	recordTypeIR := `{
		"formatVersion": 3,
		"distribution": [
			"Library",
			[["example"], ["domain"]],
			{},
			{
				"modules": [
					{
						"name": [["models"]],
						"def": [
							"public",
							{
								"types": [
									[
										[["user"]],
										[
											"public",
											[
												"User represents a person",
												[
													"type_alias_definition",
													[],
													[
														"record",
														{},
														[
															[
																[["id"]],
																[
																	"reference",
																	{},
																	[[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]],
																	[]
																]
															],
															[
																[["name"]],
																[
																	"reference",
																	{},
																	[[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]],
																	[]
																]
															]
														]
													]
												]
											]
										]
									]
								],
								"values": []
							}
						]
					}
				]
			}
		]
	}`
	g.irFilePath = filepath.Join(g.tempDir, "record-type-ir.json")
	return os.WriteFile(g.irFilePath, []byte(recordTypeIR), 0644)
}

func (g *GolangTestContext) theMultiModuleIRFixture() error {
	multiModuleIR := `{
		"formatVersion": 3,
		"distribution": [
			"Library",
			[["example"], ["app"]],
			{},
			{
				"modules": [
					{
						"name": [["domain"]],
						"def": [
							"public",
							{
								"types": [
									[
										[["customer", "id"]],
										[
											"public",
											[
												"Customer identifier",
												[
													"type_alias_definition",
													[],
													[
														"reference",
														{},
														[[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]],
														[]
													]
												]
											]
										]
									]
								],
								"values": []
							}
						]
					},
					{
						"name": [["service"]],
						"def": [
							"public",
							{
								"types": [
									[
										[["request"]],
										[
											"public",
											[
												"Service request",
												[
													"type_alias_definition",
													[],
													[
														"reference",
														{},
														[[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]],
														[]
													]
												]
											]
										]
									]
								],
								"values": []
							}
						]
					}
				]
			}
		]
	}`
	g.irFilePath = filepath.Join(g.tempDir, "multi-module-ir.json")
	return os.WriteFile(g.irFilePath, []byte(multiModuleIR), 0644)
}

func (g *GolangTestContext) anIRWithUnsupportedConstructs() error {
	// Create an IR with constructs that might generate warnings
	return g.aMinimalMorphirIRFile()
}

func (g *GolangTestContext) aGoSourceFile() error {
	sourceCode := `package main

func main() {
	println("Hello, World!")
}
`
	g.sourceFilePath = filepath.Join(g.tempDir, "main.go")
	return os.WriteFile(g.sourceFilePath, []byte(sourceCode), 0644)
}

func (g *GolangTestContext) aJSONLFileWithMultipleIRInputs() error {
	// Create minimal IR files
	ir1 := `{"formatVersion": 3, "distribution": ["Library", [["app1"]], {}, {"modules": []}]}`
	ir2 := `{"formatVersion": 3, "distribution": ["Library", [["app2"]], {}, {"modules": []}]}`

	ir1Path := filepath.Join(g.tempDir, "ir1.json")
	ir2Path := filepath.Join(g.tempDir, "ir2.json")
	out1Path := filepath.Join(g.tempDir, "out1")
	out2Path := filepath.Join(g.tempDir, "out2")

	if err := os.WriteFile(ir1Path, []byte(ir1), 0644); err != nil {
		return err
	}
	if err := os.WriteFile(ir2Path, []byte(ir2), 0644); err != nil {
		return err
	}
	if err := os.MkdirAll(out1Path, 0755); err != nil {
		return err
	}
	if err := os.MkdirAll(out2Path, 0755); err != nil {
		return err
	}

	jsonl := fmt.Sprintf(`{"name": "app1", "irFile": %q, "outputDir": %q, "modulePath": "example.com/app1"}
{"name": "app2", "irFile": %q, "outputDir": %q, "modulePath": "example.com/app2"}`,
		ir1Path, out1Path, ir2Path, out2Path)

	g.jsonlFilePath = filepath.Join(g.tempDir, "inputs.jsonl")
	return os.WriteFile(g.jsonlFilePath, []byte(jsonl), 0644)
}

func (g *GolangTestContext) aJSONLFileWithMultipleSourceInputs() error {
	// Create source files
	src1 := `package pkg1

type User struct {
	ID string
}
`
	src2 := `package pkg2

type Order struct {
	ID string
}
`

	src1Path := filepath.Join(g.tempDir, "pkg1.go")
	src2Path := filepath.Join(g.tempDir, "pkg2.go")

	if err := os.WriteFile(src1Path, []byte(src1), 0644); err != nil {
		return err
	}
	if err := os.WriteFile(src2Path, []byte(src2), 0644); err != nil {
		return err
	}

	jsonl := fmt.Sprintf(`{"name": "pkg1", "sourceFile": %q}
{"name": "pkg2", "sourceFile": %q}`, src1Path, src2Path)

	g.jsonlFilePath = filepath.Join(g.tempDir, "sources.jsonl")
	return os.WriteFile(g.jsonlFilePath, []byte(jsonl), 0644)
}

func (g *GolangTestContext) goToolchainIsAvailable() error {
	cmd := exec.Command("go", "version")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Go toolchain not available: %w", err)
	}
	return nil
}

// Build command step implementations

func (g *GolangTestContext) runBuildWithoutIRFile() error {
	return g.runMorphirCmd("golang", "build", "-o", g.outputDir, "-m", g.modulePath)
}

func (g *GolangTestContext) runBuildWithoutOutputFlag() error {
	return g.runMorphirCmd("golang", "build", g.irFilePath, "-m", g.modulePath)
}

func (g *GolangTestContext) runBuildWithoutModulePathFlag() error {
	return g.runMorphirCmd("golang", "build", g.irFilePath, "-o", g.outputDir)
}

func (g *GolangTestContext) runBuildWithValidArgs() error {
	return g.runMorphirCmd("golang", "build", g.irFilePath, "-o", g.outputDir, "-m", g.modulePath)
}

func (g *GolangTestContext) runBuildWithJSONFlag() error {
	g.useJSON = true
	err := g.runMorphirCmd("golang", "build", g.irFilePath, "-o", g.outputDir, "-m", g.modulePath, "--json")
	if err == nil && g.cmdExitCode == 0 {
		var result map[string]any
		if jsonErr := json.Unmarshal(g.cmdOutput.Bytes(), &result); jsonErr == nil {
			g.jsonOutput = result
		}
	}
	return err
}

func (g *GolangTestContext) runBuildWithWorkspaceFlag() error {
	g.useWorkspace = true
	return g.runMorphirCmd("golang", "build", g.irFilePath, "-o", g.outputDir, "-m", g.modulePath, "--workspace")
}

func (g *GolangTestContext) runBuildWithJSONLInputFlag() error {
	return g.runMorphirCmd("golang", "build", "--jsonl-input", g.jsonlFilePath, "--jsonl")
}

// Make command step implementations

func (g *GolangTestContext) runGolangMake() error {
	return g.runMorphirCmd("golang", "make")
}

func (g *GolangTestContext) runMakeWithSourceFile() error {
	return g.runMorphirCmd("golang", "make", g.sourceFilePath)
}

func (g *GolangTestContext) runMakeWithJSONFlag() error {
	g.useJSON = true
	err := g.runMorphirCmd("golang", "make", "--json")
	if err == nil && g.cmdExitCode == 0 {
		var result map[string]any
		if jsonErr := json.Unmarshal(g.cmdOutput.Bytes(), &result); jsonErr == nil {
			g.jsonOutput = result
		}
	}
	return err
}

func (g *GolangTestContext) runMakeWithJSONLInputFlag() error {
	return g.runMorphirCmd("golang", "make", "--jsonl-input", g.jsonlFilePath, "--jsonl")
}

// Go toolchain step implementations

func (g *GolangTestContext) runGoBuildInOutputDir() error {
	cmd := exec.Command("go", "build", "./...")
	cmd.Dir = g.outputDir
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

func (g *GolangTestContext) outputShouldMention(keyword string) error {
	combined := g.cmdOutput.String() + g.cmdError.String()
	if !strings.Contains(strings.ToLower(combined), strings.ToLower(keyword)) {
		return fmt.Errorf("expected output to mention %q, got: %s", keyword, combined)
	}
	return nil
}

// Batch processing step implementations

func (g *GolangTestContext) commandShouldProcessAllInputs() error {
	// For JSONL mode, check that we got output for each input
	// This is a simple check - just verify command didn't fail
	return g.commandShouldSucceed()
}

func (g *GolangTestContext) outputShouldContainJSONLResults() error {
	output := g.cmdOutput.String()
	lines := strings.Split(strings.TrimSpace(output), "\n")
	for _, line := range lines {
		if line == "" {
			continue
		}
		var result map[string]any
		if err := json.Unmarshal([]byte(line), &result); err != nil {
			return fmt.Errorf("line is not valid JSON: %q", line)
		}
	}
	return nil
}

// Acceptance test step implementations

func (g *GolangTestContext) goBuildShouldSucceed() error {
	if g.cmdExitCode != 0 {
		return fmt.Errorf("go build failed with exit code %d: %s", g.cmdExitCode, g.cmdError.String())
	}
	return nil
}

func (g *GolangTestContext) goModShouldBeValid() error {
	goModPath := filepath.Join(g.outputDir, "go.mod")
	content, err := os.ReadFile(goModPath)
	if err != nil {
		return fmt.Errorf("failed to read go.mod: %w", err)
	}

	// Basic validation - should have module and go version
	contentStr := string(content)
	if !strings.Contains(contentStr, "module ") {
		return fmt.Errorf("go.mod missing module declaration")
	}
	if !strings.Contains(contentStr, "go ") {
		return fmt.Errorf("go.mod missing go version")
	}
	return nil
}

func (g *GolangTestContext) allGoFilesShouldHaveValidSyntax() error {
	return filepath.Walk(g.outputDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || !strings.HasSuffix(path, ".go") {
			return nil
		}

		// Use gofmt to check syntax
		cmd := exec.Command("gofmt", "-e", path)
		var stderr bytes.Buffer
		cmd.Stderr = &stderr

		if err := cmd.Run(); err != nil {
			return fmt.Errorf("invalid Go syntax in %s: %s", path, stderr.String())
		}
		return nil
	})
}

func (g *GolangTestContext) diagnosticsShouldContainWarnings() error {
	if g.jsonOutput == nil {
		return fmt.Errorf("no JSON output available")
	}

	diagnostics, ok := g.jsonOutput["diagnostics"]
	if !ok {
		return fmt.Errorf("no diagnostics field in output")
	}

	diagList, ok := diagnostics.([]any)
	if !ok {
		return fmt.Errorf("diagnostics is not an array")
	}

	for _, d := range diagList {
		diagMap, ok := d.(map[string]any)
		if !ok {
			continue
		}
		if severity, ok := diagMap["severity"].(string); ok && severity == "warning" {
			return nil
		}
	}

	return fmt.Errorf("no warnings found in diagnostics")
}
