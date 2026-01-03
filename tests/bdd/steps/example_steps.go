package steps

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"

	"github.com/cucumber/godog"
	"gopkg.in/yaml.v3"
)

// TestSpec represents the test.yaml specification for an example project.
type TestSpec struct {
	Description string          `yaml:"description"`
	Workspace   WorkspaceExpect `yaml:"workspace"`
	Validate    *ValidateExpect `yaml:"validate,omitempty"`
	CLI         *CLIExpect      `yaml:"cli,omitempty"`
}

// WorkspaceExpect defines expectations for workspace loading.
type WorkspaceExpect struct {
	Loads          bool            `yaml:"loads"`
	HasRootProject bool            `yaml:"has_root_project"`
	MemberCount    int             `yaml:"member_count"`
	RootProject    *ProjectExpect  `yaml:"root_project,omitempty"`
	Members        []ProjectExpect `yaml:"members,omitempty"`
}

// ProjectExpect defines expectations for a project.
type ProjectExpect struct {
	Name            string   `yaml:"name"`
	Version         string   `yaml:"version,omitempty"`
	SourceDirectory string   `yaml:"source_directory"`
	ModulePrefix    string   `yaml:"module_prefix"`
	ExposedModules  []string `yaml:"exposed_modules"`
	ConfigFormat    string   `yaml:"config_format"`
}

// ValidateExpect defines expectations for the validate command.
type ValidateExpect struct {
	Succeeds bool   `yaml:"succeeds"`
	Error    string `yaml:"error,omitempty"`
}

// CLIExpect defines expectations for CLI commands.
type CLIExpect struct {
	ProjectList *ProjectListExpect `yaml:"project_list,omitempty"`
}

// ProjectListExpect defines expectations for the project list command.
type ProjectListExpect struct {
	Count int `yaml:"count"`
}

// DiscoveredExample represents an example project discovered in the examples/ directory.
type DiscoveredExample struct {
	Name string
	Path string
	Spec *TestSpec
}

// ExampleTestContext holds state for example-based test scenarios.
type ExampleTestContext struct {
	// TempDir is the temporary directory containing the copied example.
	TempDir string

	// ExampleName is the name of the example being tested.
	ExampleName string

	// Spec is the loaded test specification.
	Spec *TestSpec

	// LoadedWorkspace is the result of loading the workspace.
	LoadedWorkspace *LoadedWorkspaceResult

	// LastError holds the last error encountered.
	LastError error

	// DiscoveredExamples holds all discovered examples (for discovery-based testing).
	DiscoveredExamples []DiscoveredExample

	// TestResults holds results from testing multiple examples.
	TestResults []ExampleTestResult
}

// ExampleTestResult holds the result of testing a single example.
type ExampleTestResult struct {
	Name    string
	Passed  bool
	Error   error
	Details string
}

// exampleContextKey is used to store ExampleTestContext in context.Context.
type exampleContextKey struct{}

// NewExampleTestContext creates a new example test context.
func NewExampleTestContext() *ExampleTestContext {
	return &ExampleTestContext{}
}

// WithExampleTestContext attaches the example context to the Go context.
func WithExampleTestContext(ctx context.Context, etc *ExampleTestContext) context.Context {
	return context.WithValue(ctx, exampleContextKey{}, etc)
}

// GetExampleTestContext retrieves the example context from the Go context.
func GetExampleTestContext(ctx context.Context) (*ExampleTestContext, error) {
	etc, ok := ctx.Value(exampleContextKey{}).(*ExampleTestContext)
	if !ok {
		return nil, fmt.Errorf("example test context not found")
	}
	return etc, nil
}

// Cleanup removes the temporary directory.
func (etc *ExampleTestContext) Cleanup() error {
	if etc.TempDir != "" {
		return os.RemoveAll(etc.TempDir)
	}
	return nil
}

// Reset clears state for a new scenario.
func (etc *ExampleTestContext) Reset() {
	etc.ExampleName = ""
	etc.Spec = nil
	etc.LoadedWorkspace = nil
	etc.LastError = nil
	etc.DiscoveredExamples = nil
	etc.TestResults = nil
}

// RegisterExampleSteps registers all example-related step definitions.
func RegisterExampleSteps(sc *godog.ScenarioContext) {
	// Setup steps
	sc.Step(`^the example project "([^"]*)"$`, theExampleProject)

	// Workspace loading
	sc.Step(`^I load the example workspace$`, iLoadTheExampleWorkspace)

	// Expectation assertions
	sc.Step(`^all workspace expectations should pass$`, allWorkspaceExpectationsShouldPass)
	sc.Step(`^the workspace loading expectation should pass$`, workspaceLoadingExpectationShouldPass)
	sc.Step(`^the root project expectations should pass$`, rootProjectExpectationsShouldPass)
	sc.Step(`^the member expectations should pass$`, memberExpectationsShouldPass)

	// Discovery-based testing steps
	sc.Step(`^all discovered example projects$`, allDiscoveredExampleProjects)
	sc.Step(`^I test each example against its workspace expectations$`, iTestEachExampleAgainstWorkspaceExpectations)
	sc.Step(`^all examples should pass their workspace expectations$`, allExamplesShouldPassWorkspaceExpectations)
}

// getRepoRoot returns the root of the repository.
func getRepoRoot() string {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		return ""
	}
	// steps/example_steps.go -> tests/bdd/steps -> tests/bdd -> tests -> repo root
	return filepath.Join(filepath.Dir(filename), "..", "..", "..")
}

// theExampleProject copies an example project to a temp directory and loads its test.yaml.
func theExampleProject(ctx context.Context, name string) (context.Context, error) {
	etc := NewExampleTestContext()
	etc.ExampleName = name

	// Create temp directory
	tempDir, err := os.MkdirTemp("", "morphir-example-test-*")
	if err != nil {
		return ctx, fmt.Errorf("failed to create temp dir: %w", err)
	}
	etc.TempDir = tempDir

	// Copy example to temp directory
	exampleSrc := filepath.Join(getRepoRoot(), "examples", name)
	if err := copyDir(exampleSrc, tempDir); err != nil {
		os.RemoveAll(tempDir)
		return ctx, fmt.Errorf("failed to copy example %q: %w", name, err)
	}

	// Load test.yaml
	specPath := filepath.Join(tempDir, "test.yaml")
	spec, err := loadTestSpec(specPath)
	if err != nil {
		os.RemoveAll(tempDir)
		return ctx, fmt.Errorf("failed to load test.yaml for %q: %w", name, err)
	}
	etc.Spec = spec

	// Also set up WorkspaceTestContext for compatibility with existing steps
	wtc := NewWorkspaceTestContext()
	wtc.TempDir = tempDir

	ctx = WithExampleTestContext(ctx, etc)
	ctx = WithWorkspaceTestContext(ctx, wtc)
	return ctx, nil
}

// loadTestSpec loads and parses a test.yaml file.
func loadTestSpec(path string) (*TestSpec, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var spec TestSpec
	if err := yaml.Unmarshal(data, &spec); err != nil {
		return nil, err
	}

	return &spec, nil
}

// copyDir recursively copies a directory.
func copyDir(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Calculate destination path
		relPath, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		dstPath := filepath.Join(dst, relPath)

		if info.IsDir() {
			return os.MkdirAll(dstPath, info.Mode())
		}

		return copyFile(path, dstPath)
	})
}

// copyFile copies a single file.
func copyFile(src, dst string) error {
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	srcInfo, err := srcFile.Stat()
	if err != nil {
		return err
	}

	dstFile, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, srcInfo.Mode())
	if err != nil {
		return err
	}
	defer dstFile.Close()

	_, err = io.Copy(dstFile, srcFile)
	return err
}

// iLoadTheExampleWorkspace loads the workspace from the example's temp directory.
func iLoadTheExampleWorkspace(ctx context.Context) error {
	etc, err := GetExampleTestContext(ctx)
	if err != nil {
		return err
	}

	// Use existing workspace loading logic
	result, loadErr := loadWorkspaceForTest(etc.TempDir)
	etc.LoadedWorkspace = result
	etc.LastError = loadErr

	// Also update WorkspaceTestContext for compatibility
	wtc, err := GetWorkspaceTestContext(ctx)
	if err == nil {
		wtc.LoadedWorkspace = result
		wtc.LastError = loadErr
	}

	return nil
}

// allWorkspaceExpectationsShouldPass checks all workspace expectations from test.yaml.
func allWorkspaceExpectationsShouldPass(ctx context.Context) error {
	if err := workspaceLoadingExpectationShouldPass(ctx); err != nil {
		return err
	}
	if err := rootProjectExpectationsShouldPass(ctx); err != nil {
		return err
	}
	if err := memberExpectationsShouldPass(ctx); err != nil {
		return err
	}
	return nil
}

// workspaceLoadingExpectationShouldPass checks basic workspace loading expectations.
func workspaceLoadingExpectationShouldPass(ctx context.Context) error {
	etc, err := GetExampleTestContext(ctx)
	if err != nil {
		return err
	}

	spec := etc.Spec.Workspace

	// Check if workspace should load
	if spec.Loads {
		if etc.LastError != nil {
			return fmt.Errorf("expected workspace to load, but got error: %v", etc.LastError)
		}
		if etc.LoadedWorkspace == nil {
			return fmt.Errorf("expected workspace to load, but result is nil")
		}
	}

	// Check has_root_project
	hasRoot := etc.LoadedWorkspace.RootProject != nil
	if hasRoot != spec.HasRootProject {
		return fmt.Errorf("has_root_project: expected %v, got %v", spec.HasRootProject, hasRoot)
	}

	// Check member_count
	memberCount := len(etc.LoadedWorkspace.Members)
	if memberCount != spec.MemberCount {
		return fmt.Errorf("member_count: expected %d, got %d", spec.MemberCount, memberCount)
	}

	return nil
}

// rootProjectExpectationsShouldPass checks root project expectations.
func rootProjectExpectationsShouldPass(ctx context.Context) error {
	etc, err := GetExampleTestContext(ctx)
	if err != nil {
		return err
	}

	spec := etc.Spec.Workspace
	if spec.RootProject == nil {
		// No root project expectations to check
		return nil
	}

	if etc.LoadedWorkspace.RootProject == nil {
		return fmt.Errorf("expected root project, but none found")
	}

	return checkProjectExpectations("root_project", *spec.RootProject, *etc.LoadedWorkspace.RootProject)
}

// memberExpectationsShouldPass checks member project expectations.
func memberExpectationsShouldPass(ctx context.Context) error {
	etc, err := GetExampleTestContext(ctx)
	if err != nil {
		return err
	}

	spec := etc.Spec.Workspace
	if len(spec.Members) == 0 {
		// No member expectations to check
		return nil
	}

	// Build a map of actual members by name
	actualMembers := make(map[string]MemberResult)
	for _, m := range etc.LoadedWorkspace.Members {
		actualMembers[m.Name] = m
	}

	// Check each expected member
	for i, expected := range spec.Members {
		actual, ok := actualMembers[expected.Name]
		if !ok {
			return fmt.Errorf("members[%d]: expected member %q not found", i, expected.Name)
		}

		if err := checkProjectExpectations(fmt.Sprintf("members[%d]", i), expected, actual); err != nil {
			return err
		}
	}

	return nil
}

// checkProjectExpectations validates a project against expectations.
func checkProjectExpectations(prefix string, expected ProjectExpect, actual MemberResult) error {
	if expected.Name != "" && actual.Name != expected.Name {
		return fmt.Errorf("%s.name: expected %q, got %q", prefix, expected.Name, actual.Name)
	}

	if expected.Version != "" && actual.Version != expected.Version {
		return fmt.Errorf("%s.version: expected %q, got %q", prefix, expected.Version, actual.Version)
	}

	if expected.SourceDirectory != "" && actual.SourceDir != expected.SourceDirectory {
		return fmt.Errorf("%s.source_directory: expected %q, got %q", prefix, expected.SourceDirectory, actual.SourceDir)
	}

	if expected.ModulePrefix != "" && actual.ModulePrefix != expected.ModulePrefix {
		return fmt.Errorf("%s.module_prefix: expected %q, got %q", prefix, expected.ModulePrefix, actual.ModulePrefix)
	}

	if expected.ConfigFormat != "" && actual.ConfigFormat != expected.ConfigFormat {
		return fmt.Errorf("%s.config_format: expected %q, got %q", prefix, expected.ConfigFormat, actual.ConfigFormat)
	}

	if len(expected.ExposedModules) > 0 {
		// Sort both for comparison
		expectedSorted := make([]string, len(expected.ExposedModules))
		copy(expectedSorted, expected.ExposedModules)
		sort.Strings(expectedSorted)

		actualSorted := make([]string, len(actual.ExposedModules))
		copy(actualSorted, actual.ExposedModules)
		sort.Strings(actualSorted)

		if len(expectedSorted) != len(actualSorted) {
			return fmt.Errorf("%s.exposed_modules: expected %v, got %v", prefix, expectedSorted, actualSorted)
		}

		for i := range expectedSorted {
			if expectedSorted[i] != actualSorted[i] {
				return fmt.Errorf("%s.exposed_modules: expected %v, got %v", prefix, expectedSorted, actualSorted)
			}
		}
	}

	return nil
}

// discoverExamples finds all example projects with test.yaml files.
func discoverExamples() ([]DiscoveredExample, error) {
	examplesDir := filepath.Join(getRepoRoot(), "examples")

	entries, err := os.ReadDir(examplesDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read examples directory: %w", err)
	}

	var discovered []DiscoveredExample
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		examplePath := filepath.Join(examplesDir, entry.Name())
		specPath := filepath.Join(examplePath, "test.yaml")

		// Check if test.yaml exists
		if _, err := os.Stat(specPath); os.IsNotExist(err) {
			continue
		}

		// Load the spec
		spec, err := loadTestSpec(specPath)
		if err != nil {
			return nil, fmt.Errorf("failed to load test.yaml for %q: %w", entry.Name(), err)
		}

		discovered = append(discovered, DiscoveredExample{
			Name: entry.Name(),
			Path: examplePath,
			Spec: spec,
		})
	}

	// Sort by name for deterministic ordering
	sort.Slice(discovered, func(i, j int) bool {
		return discovered[i].Name < discovered[j].Name
	})

	return discovered, nil
}

// allDiscoveredExampleProjects discovers all example projects and stores them in context.
func allDiscoveredExampleProjects(ctx context.Context) (context.Context, error) {
	etc := NewExampleTestContext()

	discovered, err := discoverExamples()
	if err != nil {
		return ctx, err
	}

	if len(discovered) == 0 {
		return ctx, fmt.Errorf("no example projects found with test.yaml files")
	}

	etc.DiscoveredExamples = discovered
	return WithExampleTestContext(ctx, etc), nil
}

// iTestEachExampleAgainstWorkspaceExpectations tests each discovered example.
func iTestEachExampleAgainstWorkspaceExpectations(ctx context.Context) (context.Context, error) {
	etc, err := GetExampleTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	var results []ExampleTestResult

	for _, example := range etc.DiscoveredExamples {
		result := testExampleWorkspace(example)
		results = append(results, result)
	}

	etc.TestResults = results
	return ctx, nil
}

// testExampleWorkspace tests a single example's workspace expectations.
func testExampleWorkspace(example DiscoveredExample) ExampleTestResult {
	result := ExampleTestResult{
		Name:   example.Name,
		Passed: false,
	}

	// Create temp directory
	tempDir, err := os.MkdirTemp("", "morphir-example-test-*")
	if err != nil {
		result.Error = fmt.Errorf("failed to create temp dir: %w", err)
		return result
	}
	defer os.RemoveAll(tempDir)

	// Copy example to temp directory
	if err := copyDir(example.Path, tempDir); err != nil {
		result.Error = fmt.Errorf("failed to copy example: %w", err)
		return result
	}

	// Load workspace
	wsResult, loadErr := loadWorkspaceForTest(tempDir)

	spec := example.Spec.Workspace

	// Check if workspace should load
	if spec.Loads {
		if loadErr != nil {
			result.Error = fmt.Errorf("expected workspace to load, but got error: %v", loadErr)
			return result
		}
		if wsResult == nil {
			result.Error = fmt.Errorf("expected workspace to load, but result is nil")
			return result
		}
	}

	// Check has_root_project
	hasRoot := wsResult != nil && wsResult.RootProject != nil
	if hasRoot != spec.HasRootProject {
		result.Error = fmt.Errorf("has_root_project: expected %v, got %v", spec.HasRootProject, hasRoot)
		return result
	}

	// Check member_count
	memberCount := 0
	if wsResult != nil {
		memberCount = len(wsResult.Members)
	}
	if memberCount != spec.MemberCount {
		result.Error = fmt.Errorf("member_count: expected %d, got %d", spec.MemberCount, memberCount)
		return result
	}

	// Check root project expectations
	if spec.RootProject != nil {
		if wsResult.RootProject == nil {
			result.Error = fmt.Errorf("expected root project, but none found")
			return result
		}
		if err := checkProjectExpectations("root_project", *spec.RootProject, *wsResult.RootProject); err != nil {
			result.Error = err
			return result
		}
	}

	// Check member expectations
	if len(spec.Members) > 0 {
		actualMembers := make(map[string]MemberResult)
		for _, m := range wsResult.Members {
			actualMembers[m.Name] = m
		}

		for i, expected := range spec.Members {
			actual, ok := actualMembers[expected.Name]
			if !ok {
				result.Error = fmt.Errorf("members[%d]: expected member %q not found", i, expected.Name)
				return result
			}

			if err := checkProjectExpectations(fmt.Sprintf("members[%d]", i), expected, actual); err != nil {
				result.Error = err
				return result
			}
		}
	}

	result.Passed = true
	result.Details = fmt.Sprintf("workspace loaded with %d members, has_root=%v",
		memberCount, hasRoot)
	return result
}

// allExamplesShouldPassWorkspaceExpectations verifies all examples passed.
func allExamplesShouldPassWorkspaceExpectations(ctx context.Context) error {
	etc, err := GetExampleTestContext(ctx)
	if err != nil {
		return err
	}

	var failures []string
	var passed int

	for _, result := range etc.TestResults {
		if result.Passed {
			passed++
		} else {
			failures = append(failures, fmt.Sprintf("  - %s: %v", result.Name, result.Error))
		}
	}

	if len(failures) > 0 {
		return fmt.Errorf("%d/%d examples failed:\n%s",
			len(failures), len(etc.TestResults), joinLines(failures))
	}

	return nil
}

// joinLines joins strings with newlines.
func joinLines(lines []string) string {
	result := ""
	for i, line := range lines {
		if i > 0 {
			result += "\n"
		}
		result += line
	}
	return result
}
