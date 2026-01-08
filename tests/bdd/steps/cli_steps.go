package steps

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/cucumber/godog"
)

// CLITestContext holds state for CLI command BDD scenarios.
type CLITestContext struct {
	// WorkDir is the working directory for command execution.
	WorkDir string

	// Command is the last executed command.
	Command string

	// Args are the arguments passed to the command.
	Args []string

	// Stdout captures standard output.
	Stdout bytes.Buffer

	// Stderr captures standard error.
	Stderr bytes.Buffer

	// ExitCode is the exit code of the last command.
	ExitCode int

	// LastError holds any error from command execution.
	LastError error
}

// cliContextKey is used to store CLITestContext in context.Context.
type cliContextKey struct{}

// NewCLITestContext creates a new CLI test context.
func NewCLITestContext() *CLITestContext {
	return &CLITestContext{}
}

// WithCLITestContext attaches the CLI context to the Go context.
func WithCLITestContext(ctx context.Context, ctc *CLITestContext) context.Context {
	return context.WithValue(ctx, cliContextKey{}, ctc)
}

// GetCLITestContext retrieves the CLI context from the Go context.
func GetCLITestContext(ctx context.Context) (*CLITestContext, error) {
	ctc, ok := ctx.Value(cliContextKey{}).(*CLITestContext)
	if !ok {
		return nil, fmt.Errorf("CLI test context not found")
	}
	return ctc, nil
}

// Reset clears state for a new scenario.
func (ctc *CLITestContext) Reset() {
	ctc.WorkDir = ""
	ctc.Command = ""
	ctc.Args = nil
	ctc.Stdout.Reset()
	ctc.Stderr.Reset()
	ctc.ExitCode = 0
	ctc.LastError = nil
}

// getMorphirBinary returns the path to the morphir CLI binary.
func getMorphirBinary() string {
	// Build path relative to repo root
	repoRoot := getRepoRoot()
	binary := filepath.Join(repoRoot, "cmd", "morphir", "morphir")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	return binary
}

// buildMorphirCLI builds the morphir CLI if needed.
func buildMorphirCLI() error {
	binary := getMorphirBinary()

	// Check if binary exists and is recent
	if info, err := os.Stat(binary); err == nil {
		// Binary exists - check if source is newer
		srcDir := filepath.Join(getRepoRoot(), "cmd", "morphir")
		srcInfo, srcErr := os.Stat(srcDir)
		if srcErr == nil && info.ModTime().After(srcInfo.ModTime()) {
			// Binary is newer than source dir, skip build
			return nil
		}
	}

	// Build the binary
	cmd := exec.Command("go", "build", "-o", binary, ".")
	cmd.Dir = filepath.Join(getRepoRoot(), "cmd", "morphir")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to build morphir CLI: %w\n%s", err, output)
	}
	return nil
}

// RegisterCLISteps registers all CLI-related step definitions.
func RegisterCLISteps(sc *godog.ScenarioContext) {
	// Setup steps
	sc.Step(`^the morphir CLI is available$`, theMorphirCLIIsAvailable)
	sc.Step(`^I am in the directory "([^"]*)"$`, iAmInTheDirectory)
	sc.Step(`^I am in a temporary directory$`, iAmInATemporaryDirectory)
	sc.Step(`^the IR file "([^"]*)" exists$`, theIRFileExists)

	// Command execution
	sc.Step(`^I run morphir validate "([^"]*)"$`, iRunMorphirValidate)
	sc.Step(`^I run morphir validate "([^"]*)" with --json$`, iRunMorphirValidateWithJSON)
	sc.Step(`^I run morphir validate$`, iRunMorphirValidateNoArgs)
	sc.Step(`^I run morphir validate on fixture "([^"]*)"$`, iRunMorphirValidateOnFixture)
	sc.Step(`^I run morphir validate on fixture "([^"]*)" with --json$`, iRunMorphirValidateOnFixtureWithJSON)
	sc.Step(`^I run morphir validate on fixture "([^"]*)" with --report markdown$`, iRunMorphirValidateOnFixtureWithReportMarkdown)

	// Assertions - exit code
	sc.Step(`^the command should succeed$`, theCommandShouldSucceed)
	sc.Step(`^the command should fail$`, theCommandShouldFail)
	sc.Step(`^the exit code should be (\d+)$`, theExitCodeShouldBe)

	// Assertions - output
	sc.Step(`^the output should contain "([^"]*)"$`, theOutputShouldContain)
	sc.Step(`^the output should not contain "([^"]*)"$`, theOutputShouldNotContain)
	sc.Step(`^the output should match "([^"]*)"$`, theOutputShouldMatch)
	sc.Step(`^the JSON output should have "([^"]*)" equal to "([^"]*)"$`, theJSONOutputShouldHaveStringEqual)
	sc.Step(`^the JSON output should have "([^"]*)" equal to (true|false)$`, theJSONOutputShouldHaveBoolEqual)
	sc.Step(`^the JSON output should have "([^"]*)" equal to (\d+)$`, theJSONOutputShouldHaveIntEqual)
}

// Step implementations

func theMorphirCLIIsAvailable(ctx context.Context) (context.Context, error) {
	ctc := NewCLITestContext()

	if err := buildMorphirCLI(); err != nil {
		return ctx, err
	}

	return WithCLITestContext(ctx, ctc), nil
}

func iAmInTheDirectory(ctx context.Context, dir string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	// If relative, make it relative to repo root
	if !filepath.IsAbs(dir) {
		dir = filepath.Join(getRepoRoot(), dir)
	}

	if _, err := os.Stat(dir); err != nil {
		return fmt.Errorf("directory not found: %s", dir)
	}

	ctc.WorkDir = dir
	return nil
}

func iAmInATemporaryDirectory(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	tmpDir, err := os.MkdirTemp("", "morphir-cli-test-*")
	if err != nil {
		return fmt.Errorf("failed to create temp dir: %w", err)
	}

	ctc.WorkDir = tmpDir
	return nil
}

func theIRFileExists(ctx context.Context, filename string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	// Copy from testdata if it's a known fixture
	srcPath := filepath.Join(getRepoRoot(), "tests", "bdd", "testdata", "morphir-elm", "cli-test-ir", filename)
	if _, err := os.Stat(srcPath); err == nil {
		dstPath := filepath.Join(ctc.WorkDir, "morphir.ir.json")
		data, err := os.ReadFile(srcPath)
		if err != nil {
			return fmt.Errorf("failed to read fixture: %w", err)
		}
		if err := os.WriteFile(dstPath, data, 0644); err != nil {
			return fmt.Errorf("failed to write IR file: %w", err)
		}
		return nil
	}

	return fmt.Errorf("IR fixture not found: %s", filename)
}

func iRunMorphirValidate(ctx context.Context, path string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	return runMorphirCommand(ctc, "validate", path)
}

func iRunMorphirValidateWithJSON(ctx context.Context, path string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	return runMorphirCommand(ctc, "validate", path, "--json")
}

func iRunMorphirValidateNoArgs(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	return runMorphirCommand(ctc, "validate")
}

func iRunMorphirValidateOnFixture(ctx context.Context, fixture string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	fixturePath := getIRFixturePath(fixture)
	return runMorphirCommand(ctc, "validate", fixturePath)
}

func iRunMorphirValidateOnFixtureWithJSON(ctx context.Context, fixture string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	fixturePath := getIRFixturePath(fixture)
	return runMorphirCommand(ctc, "validate", fixturePath, "--json")
}

func iRunMorphirValidateOnFixtureWithReportMarkdown(ctx context.Context, fixture string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	fixturePath := getIRFixturePath(fixture)
	return runMorphirCommand(ctc, "validate", fixturePath, "--report", "markdown")
}

// getIRFixturePath returns the absolute path to an IR fixture file.
func getIRFixturePath(filename string) string {
	return filepath.Join(getRepoRoot(), "tests", "bdd", "testdata", "morphir-elm", "cli-test-ir", filename)
}

func runMorphirCommand(ctc *CLITestContext, args ...string) error {
	binary := getMorphirBinary()

	cmd := exec.Command(binary, args...)
	cmd.Dir = ctc.WorkDir
	cmd.Stdout = &ctc.Stdout
	cmd.Stderr = &ctc.Stderr

	ctc.Command = binary
	ctc.Args = args

	err := cmd.Run()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			ctc.ExitCode = exitErr.ExitCode()
		} else {
			ctc.LastError = err
			return nil // Don't fail the step - let assertions check
		}
	} else {
		ctc.ExitCode = 0
	}

	return nil
}

func theCommandShouldSucceed(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	if ctc.LastError != nil {
		return fmt.Errorf("command failed to run: %v", ctc.LastError)
	}

	if ctc.ExitCode != 0 {
		return fmt.Errorf("command exited with code %d, expected 0\nstdout: %s\nstderr: %s",
			ctc.ExitCode, ctc.Stdout.String(), ctc.Stderr.String())
	}

	return nil
}

func theCommandShouldFail(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	if ctc.ExitCode == 0 && ctc.LastError == nil {
		return fmt.Errorf("command succeeded, expected failure\nstdout: %s", ctc.Stdout.String())
	}

	return nil
}

func theExitCodeShouldBe(ctx context.Context, expected int) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	if ctc.ExitCode != expected {
		return fmt.Errorf("exit code: expected %d, got %d", expected, ctc.ExitCode)
	}

	return nil
}

func theOutputShouldContain(ctx context.Context, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	combined := ctc.Stdout.String() + ctc.Stderr.String()
	if !strings.Contains(combined, expected) {
		return fmt.Errorf("output does not contain %q\nactual output: %s", expected, combined)
	}

	return nil
}

func theOutputShouldNotContain(ctx context.Context, unexpected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	combined := ctc.Stdout.String() + ctc.Stderr.String()
	if strings.Contains(combined, unexpected) {
		return fmt.Errorf("output unexpectedly contains %q\nactual output: %s", unexpected, combined)
	}

	return nil
}

func theOutputShouldMatch(ctx context.Context, pattern string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	combined := ctc.Stdout.String() + ctc.Stderr.String()
	// Simple glob-like matching
	if !strings.Contains(combined, pattern) {
		return fmt.Errorf("output does not match pattern %q\nactual output: %s", pattern, combined)
	}

	return nil
}

func theJSONOutputShouldHaveStringEqual(ctx context.Context, key, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	var result map[string]interface{}
	if err := json.Unmarshal(ctc.Stdout.Bytes(), &result); err != nil {
		return fmt.Errorf("failed to parse JSON output: %w\noutput: %s", err, ctc.Stdout.String())
	}

	actual, ok := result[key].(string)
	if !ok {
		return fmt.Errorf("key %q not found or not a string in JSON output", key)
	}

	if actual != expected {
		return fmt.Errorf("JSON output %q: expected %q, got %q", key, expected, actual)
	}

	return nil
}

func theJSONOutputShouldHaveBoolEqual(ctx context.Context, key, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	var result map[string]interface{}
	if err := json.Unmarshal(ctc.Stdout.Bytes(), &result); err != nil {
		return fmt.Errorf("failed to parse JSON output: %w\noutput: %s", err, ctc.Stdout.String())
	}

	actual, ok := result[key].(bool)
	if !ok {
		return fmt.Errorf("key %q not found or not a boolean in JSON output", key)
	}

	expectedBool := expected == "true"
	if actual != expectedBool {
		return fmt.Errorf("JSON output %q: expected %v, got %v", key, expectedBool, actual)
	}

	return nil
}

func theJSONOutputShouldHaveIntEqual(ctx context.Context, key string, expected int) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	var result map[string]interface{}
	if err := json.Unmarshal(ctc.Stdout.Bytes(), &result); err != nil {
		return fmt.Errorf("failed to parse JSON output: %w\noutput: %s", err, ctc.Stdout.String())
	}

	// JSON numbers are float64
	actual, ok := result[key].(float64)
	if !ok {
		return fmt.Errorf("key %q not found or not a number in JSON output", key)
	}

	if int(actual) != expected {
		return fmt.Errorf("JSON output %q: expected %d, got %d", key, expected, int(actual))
	}

	return nil
}

// ============================================================================
// WIT JSONL CLI Steps
// ============================================================================

// RegisterWITCLISteps registers WIT CLI step definitions including JSONL support.
func RegisterWITCLISteps(sc *godog.ScenarioContext) {
	// WIT make/build commands
	sc.Step(`^I run morphir wit make with source "([^"]*)" and --jsonl$`, iRunMorphirWitMakeWithSourceAndJSONL)
	sc.Step(`^I run morphir wit build with source "([^"]*)" and --jsonl$`, iRunMorphirWitBuildWithSourceAndJSONL)
	sc.Step(`^I run morphir wit make with --jsonl-input and --jsonl$`, iRunMorphirWitMakeWithJSONLInputAndJSONL)
	sc.Step(`^I run morphir wit make with --jsonl-input - and --jsonl$`, iRunMorphirWitMakeWithJSONLInputStdinAndJSONL)

	// JSONL input setup
	sc.Step(`^a JSONL input file with the following entries:$`, aJSONLInputFileWithEntries)
	sc.Step(`^JSONL input via stdin:$`, jsonlInputViaStdin)

	// JSONL output assertions
	sc.Step(`^the JSONL output should have "([^"]*)" equal to (true|false)$`, theJSONLOutputShouldHaveBoolEqual)
	sc.Step(`^the JSONL output should have "([^"]*)" equal to (\d+)$`, theJSONLOutputShouldHaveIntEqual)
	sc.Step(`^the JSONL output should have "([^"]*)" equal to "([^"]*)"$`, theJSONLOutputShouldHaveStringEqual)
	sc.Step(`^the JSONL output should have diagnostics with code "([^"]*)"$`, theJSONLOutputShouldHaveDiagnosticsWithCode)
	sc.Step(`^the JSONL output should have diagnostics with severity "([^"]*)"$`, theJSONLOutputShouldHaveDiagnosticsWithSeverity)

	// JSONL module assertions
	sc.Step(`^the JSONL module should have sourcePackage namespace "([^"]*)"$`, theJSONLModuleShouldHaveNamespace)
	sc.Step(`^the JSONL module should have sourcePackage name "([^"]*)"$`, theJSONLModuleShouldHaveName)
	sc.Step(`^the JSONL module should have (\d+) values$`, theJSONLModuleShouldHaveNValues)
	sc.Step(`^the JSONL module should have (\d+) types$`, theJSONLModuleShouldHaveNTypes)

	// Batch JSONL assertions
	sc.Step(`^the output should contain (\d+) JSONL lines$`, theOutputShouldContainNJSONLLines)
	sc.Step(`^JSONL line (\d+) should have "([^"]*)" equal to "([^"]*)"$`, jsonlLineShouldHaveStringEqual)
	sc.Step(`^JSONL line (\d+) should have "([^"]*)" equal to (true|false)$`, jsonlLineShouldHaveBoolEqual)
}

// jsonlInputFile stores the path to a temporary JSONL input file
var jsonlInputFile string

// jsonlStdinContent stores content to be piped to stdin
var jsonlStdinContent string

func iRunMorphirWitMakeWithSourceAndJSONL(ctx context.Context, source string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "wit", "make", "-s", source, "--jsonl")
}

func iRunMorphirWitBuildWithSourceAndJSONL(ctx context.Context, source string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "wit", "build", "-s", source, "--jsonl")
}

func aJSONLInputFileWithEntries(ctx context.Context, table *godog.Table) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	// Create temp file for JSONL input
	tmpFile, err := os.CreateTemp("", "wit-jsonl-input-*.jsonl")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}

	// Write JSONL entries from table
	for i, row := range table.Rows {
		if i == 0 {
			continue // Skip header
		}
		name := row.Cells[0].Value
		source := row.Cells[1].Value

		entry := map[string]string{"name": name, "source": source}
		data, err := json.Marshal(entry)
		if err != nil {
			return fmt.Errorf("failed to marshal entry: %w", err)
		}
		tmpFile.Write(data)
		tmpFile.WriteString("\n")
	}
	tmpFile.Close()

	jsonlInputFile = tmpFile.Name()
	// Ensure cleanup
	ctc.WorkDir = filepath.Dir(tmpFile.Name())

	return nil
}

func jsonlInputViaStdin(ctx context.Context, content *godog.DocString) error {
	jsonlStdinContent = content.Content
	return nil
}

func iRunMorphirWitMakeWithJSONLInputAndJSONL(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	if jsonlInputFile == "" {
		return fmt.Errorf("no JSONL input file set")
	}
	return runMorphirCommand(ctc, "wit", "make", "--jsonl-input", jsonlInputFile, "--jsonl")
}

func iRunMorphirWitMakeWithJSONLInputStdinAndJSONL(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	binary := getMorphirBinary()
	cmd := exec.Command(binary, "wit", "make", "--jsonl-input", "-", "--jsonl")
	cmd.Dir = ctc.WorkDir
	cmd.Stdin = strings.NewReader(jsonlStdinContent)
	cmd.Stdout = &ctc.Stdout
	cmd.Stderr = &ctc.Stderr

	ctc.Command = binary
	ctc.Args = []string{"wit", "make", "--jsonl-input", "-", "--jsonl"}

	err = cmd.Run()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			ctc.ExitCode = exitErr.ExitCode()
		} else {
			ctc.LastError = err
		}
	} else {
		ctc.ExitCode = 0
	}

	return nil
}

// parseFirstJSONLLine parses the first line of JSONL output
func parseFirstJSONLLine(output string) (map[string]interface{}, error) {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) == 0 || lines[0] == "" {
		return nil, fmt.Errorf("no JSONL output")
	}

	var result map[string]interface{}
	if err := json.Unmarshal([]byte(lines[0]), &result); err != nil {
		return nil, fmt.Errorf("failed to parse JSONL: %w\nline: %s", err, lines[0])
	}
	return result, nil
}

// parseJSONLLine parses a specific line (1-indexed) from JSONL output
func parseJSONLLine(output string, lineNum int) (map[string]interface{}, error) {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	if lineNum < 1 || lineNum > len(lines) {
		return nil, fmt.Errorf("line %d out of range (have %d lines)", lineNum, len(lines))
	}

	var result map[string]interface{}
	if err := json.Unmarshal([]byte(lines[lineNum-1]), &result); err != nil {
		return nil, fmt.Errorf("failed to parse JSONL line %d: %w\nline: %s", lineNum, err, lines[lineNum-1])
	}
	return result, nil
}

func theJSONLOutputShouldHaveBoolEqual(ctx context.Context, key, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseFirstJSONLLine(ctc.Stdout.String())
	if err != nil {
		return err
	}

	actual, ok := result[key].(bool)
	if !ok {
		return fmt.Errorf("key %q not found or not boolean in JSONL output: %v", key, result)
	}

	expectedBool := expected == "true"
	if actual != expectedBool {
		return fmt.Errorf("JSONL %q: expected %v, got %v", key, expectedBool, actual)
	}

	return nil
}

func theJSONLOutputShouldHaveIntEqual(ctx context.Context, key string, expected int) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseFirstJSONLLine(ctc.Stdout.String())
	if err != nil {
		return err
	}

	actual, ok := result[key].(float64)
	if !ok {
		// Key might not exist for failed cases, check if expected is 0
		if expected == 0 {
			return nil
		}
		return fmt.Errorf("key %q not found or not a number in JSONL output: %v", key, result)
	}

	if int(actual) != expected {
		return fmt.Errorf("JSONL %q: expected %d, got %d", key, expected, int(actual))
	}

	return nil
}

func theJSONLOutputShouldHaveStringEqual(ctx context.Context, key, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseFirstJSONLLine(ctc.Stdout.String())
	if err != nil {
		return err
	}

	actual, ok := result[key].(string)
	if !ok {
		return fmt.Errorf("key %q not found or not a string in JSONL output", key)
	}

	if actual != expected {
		return fmt.Errorf("JSONL %q: expected %q, got %q", key, expected, actual)
	}

	return nil
}

func theJSONLOutputShouldHaveDiagnosticsWithCode(ctx context.Context, code string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseFirstJSONLLine(ctc.Stdout.String())
	if err != nil {
		return err
	}

	diagnostics, ok := result["diagnostics"].([]interface{})
	if !ok || len(diagnostics) == 0 {
		return fmt.Errorf("no diagnostics found in JSONL output")
	}

	for _, d := range diagnostics {
		diag, ok := d.(map[string]interface{})
		if !ok {
			continue
		}
		if diag["code"] == code {
			return nil
		}
	}

	return fmt.Errorf("diagnostic with code %q not found", code)
}

func theJSONLOutputShouldHaveDiagnosticsWithSeverity(ctx context.Context, severity string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseFirstJSONLLine(ctc.Stdout.String())
	if err != nil {
		return err
	}

	diagnostics, ok := result["diagnostics"].([]interface{})
	if !ok || len(diagnostics) == 0 {
		return fmt.Errorf("no diagnostics found in JSONL output")
	}

	for _, d := range diagnostics {
		diag, ok := d.(map[string]interface{})
		if !ok {
			continue
		}
		if diag["severity"] == severity {
			return nil
		}
	}

	return fmt.Errorf("diagnostic with severity %q not found", severity)
}

func theJSONLModuleShouldHaveNamespace(ctx context.Context, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseFirstJSONLLine(ctc.Stdout.String())
	if err != nil {
		return err
	}

	module, ok := result["module"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("module not found in JSONL output")
	}

	sourcePackage, ok := module["sourcePackage"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("sourcePackage not found in module")
	}

	actual, ok := sourcePackage["namespace"].(string)
	if !ok {
		return fmt.Errorf("namespace not found in sourcePackage")
	}

	if actual != expected {
		return fmt.Errorf("namespace: expected %q, got %q", expected, actual)
	}

	return nil
}

func theJSONLModuleShouldHaveName(ctx context.Context, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseFirstJSONLLine(ctc.Stdout.String())
	if err != nil {
		return err
	}

	module, ok := result["module"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("module not found in JSONL output")
	}

	sourcePackage, ok := module["sourcePackage"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("sourcePackage not found in module")
	}

	actual, ok := sourcePackage["name"].(string)
	if !ok {
		return fmt.Errorf("name not found in sourcePackage")
	}

	if actual != expected {
		return fmt.Errorf("name: expected %q, got %q", expected, actual)
	}

	return nil
}

func theJSONLModuleShouldHaveNValues(ctx context.Context, expected int) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseFirstJSONLLine(ctc.Stdout.String())
	if err != nil {
		return err
	}

	module, ok := result["module"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("module not found in JSONL output")
	}

	values, ok := module["values"].([]interface{})
	if !ok {
		if expected == 0 {
			return nil
		}
		return fmt.Errorf("values not found in module")
	}

	if len(values) != expected {
		return fmt.Errorf("values count: expected %d, got %d", expected, len(values))
	}

	return nil
}

func theJSONLModuleShouldHaveNTypes(ctx context.Context, expected int) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseFirstJSONLLine(ctc.Stdout.String())
	if err != nil {
		return err
	}

	module, ok := result["module"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("module not found in JSONL output")
	}

	types, ok := module["types"].([]interface{})
	if !ok {
		if expected == 0 {
			return nil
		}
		return fmt.Errorf("types not found in module")
	}

	if len(types) != expected {
		return fmt.Errorf("types count: expected %d, got %d", expected, len(types))
	}

	return nil
}

func theOutputShouldContainNJSONLLines(ctx context.Context, expected int) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	lines := strings.Split(strings.TrimSpace(ctc.Stdout.String()), "\n")
	// Filter out empty lines
	nonEmpty := 0
	for _, line := range lines {
		if strings.TrimSpace(line) != "" {
			nonEmpty++
		}
	}

	if nonEmpty != expected {
		return fmt.Errorf("expected %d JSONL lines, got %d\noutput: %s", expected, nonEmpty, ctc.Stdout.String())
	}

	return nil
}

func jsonlLineShouldHaveStringEqual(ctx context.Context, lineNum int, key, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseJSONLLine(ctc.Stdout.String(), lineNum)
	if err != nil {
		return err
	}

	actual, ok := result[key].(string)
	if !ok {
		return fmt.Errorf("line %d: key %q not found or not a string", lineNum, key)
	}

	if actual != expected {
		return fmt.Errorf("line %d: %q expected %q, got %q", lineNum, key, expected, actual)
	}

	return nil
}

func jsonlLineShouldHaveBoolEqual(ctx context.Context, lineNum int, key, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	result, err := parseJSONLLine(ctc.Stdout.String(), lineNum)
	if err != nil {
		return err
	}

	actual, ok := result[key].(bool)
	if !ok {
		return fmt.Errorf("line %d: key %q not found or not boolean", lineNum, key)
	}

	expectedBool := expected == "true"
	if actual != expectedBool {
		return fmt.Errorf("line %d: %q expected %v, got %v", lineNum, key, expectedBool, actual)
	}

	return nil
}
