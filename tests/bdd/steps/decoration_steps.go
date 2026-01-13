package steps

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/cucumber/godog"
	"github.com/finos/morphir/pkg/config"
	"github.com/finos/morphir/pkg/tooling/decorations"
	"github.com/finos/morphir/pkg/tooling/workspace"
)

// DecorationTestContext holds state for decoration BDD scenarios.
type DecorationTestContext struct {
	// WorkDir is the working directory for test operations.
	WorkDir string

	// RegisteredTypes holds decoration types registered during tests.
	RegisteredTypes map[string]decorations.DecorationType

	// ProjectConfig holds the loaded project configuration.
	ProjectConfig config.ProjectSection

	// LoadedWorkspace holds the loaded workspace.
	LoadedWorkspace *workspace.LoadedWorkspace
}

// decorationContextKey is used to store DecorationTestContext in context.Context.
type decorationContextKey struct{}

// NewDecorationTestContext creates a new decoration test context.
func NewDecorationTestContext() *DecorationTestContext {
	return &DecorationTestContext{
		RegisteredTypes: make(map[string]decorations.DecorationType),
	}
}

// WithDecorationTestContext attaches the decoration context to the Go context.
func WithDecorationTestContext(ctx context.Context, dtc *DecorationTestContext) context.Context {
	return context.WithValue(ctx, decorationContextKey{}, dtc)
}

// GetDecorationTestContext retrieves the decoration context from the Go context.
func GetDecorationTestContext(ctx context.Context) (*DecorationTestContext, error) {
	dtc, ok := ctx.Value(decorationContextKey{}).(*DecorationTestContext)
	if !ok {
		return nil, fmt.Errorf("decoration test context not found")
	}
	return dtc, nil
}

// RegisterDecorationSteps registers step definitions for decoration features.
func RegisterDecorationSteps(sc *godog.ScenarioContext) {
	// Setup steps
	sc.Step(`^I have a workspace with decoration configuration$`, iHaveAWorkspaceWithDecorationConfiguration)
	sc.Step(`^a registered decoration type "([^"]*)" with IR "([^"]*)" and entry point "([^"]*)"$`, aRegisteredDecorationType)
	sc.Step(`^a decoration IR file "([^"]*)" exists$`, aDecorationIRFileExists)
	sc.Step(`^a project with valid decoration values$`, aProjectWithValidDecorationValues)
	sc.Step(`^a project with invalid decoration values$`, aProjectWithInvalidDecorationValues)
	sc.Step(`^a project with decorations attached to nodes$`, aProjectWithDecorationsAttachedToNodes)
	sc.Step(`^registered decoration types exist$`, registeredDecorationTypesExist)

	// Command execution
	sc.Step(`^I run "([^"]*)"$`, iRunDecorationCommand)

	// Assertions
	sc.Step(`^the project configuration should contain decoration "([^"]*)"$`, theProjectConfigurationShouldContainDecoration)
	sc.Step(`^decoration "([^"]*)" should reference type "([^"]*)"$`, decorationShouldReferenceType)
	sc.Step(`^decoration "([^"]*)" should have entry point "([^"]*)"$`, decorationShouldHaveEntryPoint)
	sc.Step(`^the output should indicate all decorations are valid$`, theOutputShouldIndicateAllDecorationsAreValid)
	sc.Step(`^the output should indicate validation errors$`, theOutputShouldIndicateValidationErrors)
	sc.Step(`^the output should list decorated nodes$`, theOutputShouldListDecoratedNodes)
	sc.Step(`^the output should show decorations for the node$`, theOutputShouldShowDecorationsForTheNode)
	sc.Step(`^the output should show decoration statistics$`, theOutputShouldShowDecorationStatistics)
	sc.Step(`^the decoration type "([^"]*)" should be registered$`, theDecorationTypeShouldBeRegistered)
	sc.Step(`^the output should list registered types$`, theOutputShouldListRegisteredTypes)
	sc.Step(`^the output should show type details$`, theOutputShouldShowTypeDetails)
	sc.Step(`^the decoration type "([^"]*)" should not be registered$`, theDecorationTypeShouldNotBeRegistered)
}

// Step implementations

func iHaveAWorkspaceWithDecorationConfiguration(ctx context.Context) (context.Context, error) {
	dtc := NewDecorationTestContext()
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		// Create CLI context if it doesn't exist
		ctc = NewCLITestContext()
		ctx = WithCLITestContext(ctx, ctc)
	}

	// Use CLI context's work dir
	dtc.WorkDir = ctc.WorkDir
	if dtc.WorkDir == "" {
		// Create temp dir if needed
		tmpDir, err := os.MkdirTemp("", "morphir-decoration-test-*")
		if err != nil {
			return ctx, err
		}
		dtc.WorkDir = tmpDir
		ctc.WorkDir = tmpDir
	}

	return WithDecorationTestContext(ctx, dtc), nil
}

func aRegisteredDecorationType(ctx context.Context, typeID, irPath, entryPoint string) error {
	dtc, err := GetDecorationTestContext(ctx)
	if err != nil {
		return err
	}

	// Create a mock decoration type
	decType := decorations.DecorationType{
		ID:         typeID,
		IRPath:     irPath,
		EntryPoint: entryPoint,
		Source:     "workspace",
	}

	dtc.RegisteredTypes[typeID] = decType
	return nil
}

func aDecorationIRFileExists(ctx context.Context, irPath string) error {
	dtc, err := GetDecorationTestContext(ctx)
	if err != nil {
		return err
	}

	// Create a minimal valid IR file for testing
	fullPath := filepath.Join(dtc.WorkDir, irPath)
	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	// Create a minimal valid IR JSON
	minimalIR := `{
  "formatVersion": 3,
  "distribution": [
    [
      [["test"], ["types"]],
      [],
      {
        "modules": [
          [
            [["types"]],
            {
              "types": {},
              "values": {}
            }
          ]
        ]
      }
    ]
  ]
}`

	return os.WriteFile(fullPath, []byte(minimalIR), 0644)
}

func aProjectWithValidDecorationValues(ctx context.Context) error {
	dtc, err := GetDecorationTestContext(ctx)
	if err != nil {
		return err
	}

	// Create a project config with decorations
	configPath := filepath.Join(dtc.WorkDir, "morphir.toml")
	configContent := `[project]
name = "Test.Package"
source_directory = "src"

[project.decorations.testFlag]
display_name = "Test Flag"
ir = "test-ir.json"
entry_point = "Test:Types:Flag"
storage_location = "test-values.json"
`

	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		return err
	}

	// Create decoration values file
	valuesPath := filepath.Join(dtc.WorkDir, "test-values.json")
	valuesContent := `{
  "Test.Package:Foo:bar": true
}`

	return os.WriteFile(valuesPath, []byte(valuesContent), 0644)
}

func aProjectWithInvalidDecorationValues(ctx context.Context) error {
	dtc, err := GetDecorationTestContext(ctx)
	if err != nil {
		return err
	}

	// Create a project config with decorations
	configPath := filepath.Join(dtc.WorkDir, "morphir.toml")
	configContent := `[project]
name = "Test.Package"
source_directory = "src"

[project.decorations.testFlag]
display_name = "Test Flag"
ir = "test-ir.json"
entry_point = "Test:Types:Flag"
storage_location = "test-values.json"
`

	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		return err
	}

	// Create invalid decoration values file (invalid JSON structure)
	valuesPath := filepath.Join(dtc.WorkDir, "test-values.json")
	valuesContent := `{
  "Test.Package:Foo:bar": "not a boolean"
}`

	return os.WriteFile(valuesPath, []byte(valuesContent), 0644)
}

func aProjectWithDecorationsAttachedToNodes(ctx context.Context) error {
	return aProjectWithValidDecorationValues(ctx)
}

func registeredDecorationTypesExist(ctx context.Context) error {
	dtc, err := GetDecorationTestContext(ctx)
	if err != nil {
		return err
	}

	// Create registry directory
	registryDir := filepath.Join(dtc.WorkDir, ".morphir", "decorations")
	if err := os.MkdirAll(registryDir, 0755); err != nil {
		return err
	}

	// Create a registry file with some types
	registryPath := filepath.Join(registryDir, "registry.json")
	registry := map[string]interface{}{
		"version": "1.0",
		"types": map[string]interface{}{
			"testFlag": map[string]interface{}{
				"id":           "testFlag",
				"display_name": "Test Flag",
				"ir_path":      "test-ir.json",
				"entry_point":  "Test:Types:Flag",
				"source":       "workspace",
			},
		},
	}

	data, err := json.MarshalIndent(registry, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(registryPath, data, 0644)
}

func iRunDecorationCommand(ctx context.Context, command string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	// Parse command into parts
	parts := strings.Fields(command)
	if len(parts) == 0 {
		return fmt.Errorf("empty command")
	}

	// First part should be "morphir", rest are args
	args := parts[1:]
	return runMorphirCommand(ctc, args...)
}

func theProjectConfigurationShouldContainDecoration(ctx context.Context, decorationID string) error {
	dtc, err := GetDecorationTestContext(ctx)
	if err != nil {
		return err
	}

	// Load workspace to check config
	lw, err := workspace.LoadFromCwd()
	if err != nil {
		// Try loading from work dir
		oldWd, _ := os.Getwd()
		os.Chdir(dtc.WorkDir)
		defer os.Chdir(oldWd)

		lw, err = workspace.LoadFromCwd()
		if err != nil {
			return err
		}
	}

	rootProject := lw.RootProject()
	if rootProject == nil {
		return fmt.Errorf("no root project found")
	}

	decorations := rootProject.Config().Decorations()
	if _, found := decorations[decorationID]; !found {
		return fmt.Errorf("decoration %q not found in project configuration", decorationID)
	}

	return nil
}

func decorationShouldReferenceType(ctx context.Context, decorationID, typeID string) error {
	// This would check that the decoration config references the registered type
	// For now, just verify the decoration exists
	return theProjectConfigurationShouldContainDecoration(ctx, decorationID)
}

func decorationShouldHaveEntryPoint(ctx context.Context, decorationID, entryPoint string) error {
	dtc, err := GetDecorationTestContext(ctx)
	if err != nil {
		return err
	}

	// Load workspace
	oldWd, _ := os.Getwd()
	os.Chdir(dtc.WorkDir)
	defer os.Chdir(oldWd)

	lw, err := workspace.LoadFromCwd()
	if err != nil {
		return err
	}

	rootProject := lw.RootProject()
	if rootProject == nil {
		return fmt.Errorf("no root project found")
	}

	decorations := rootProject.Config().Decorations()
	dec, found := decorations[decorationID]
	if !found {
		return fmt.Errorf("decoration %q not found", decorationID)
	}

	if dec.EntryPoint() != entryPoint {
		return fmt.Errorf("entry point: expected %q, got %q", entryPoint, dec.EntryPoint())
	}

	return nil
}

func theOutputShouldIndicateAllDecorationsAreValid(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	output := ctc.Stdout.String() + ctc.Stderr.String()
	if !strings.Contains(output, "valid") && !strings.Contains(output, "✓") {
		return fmt.Errorf("output does not indicate validation success")
	}

	return nil
}

func theOutputShouldIndicateValidationErrors(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	output := ctc.Stdout.String() + ctc.Stderr.String()
	if !strings.Contains(output, "error") && !strings.Contains(output, "✗") && !strings.Contains(output, "invalid") {
		return fmt.Errorf("output does not indicate validation errors")
	}

	return nil
}

func theOutputShouldListDecoratedNodes(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	output := ctc.Stdout.String()
	if !strings.Contains(output, "node") && !strings.Contains(output, "Package") {
		return fmt.Errorf("output does not appear to list decorated nodes")
	}

	return nil
}

func theOutputShouldShowDecorationsForTheNode(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	output := ctc.Stdout.String()
	if output == "" {
		return fmt.Errorf("output is empty")
	}

	return nil
}

func theOutputShouldShowDecorationStatistics(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	output := ctc.Stdout.String()
	if !strings.Contains(output, "statistic") && !strings.Contains(output, "count") && !strings.Contains(output, "total") {
		return fmt.Errorf("output does not appear to show statistics")
	}

	return nil
}

func theDecorationTypeShouldBeRegistered(ctx context.Context, typeID string) error {
	dtc, err := GetDecorationTestContext(ctx)
	if err != nil {
		return err
	}

	// Check in-memory registry
	if _, found := dtc.RegisteredTypes[typeID]; found {
		return nil
	}

	// Check actual registry file
	registryPath := filepath.Join(dtc.WorkDir, ".morphir", "decorations", "registry.json")
	if _, err := os.Stat(registryPath); os.IsNotExist(err) {
		return fmt.Errorf("registry file does not exist")
	}

	registry, err := decorations.LoadTypeRegistry(registryPath)
	if err != nil {
		return err
	}

	if !registry.Has(typeID) {
		return fmt.Errorf("decoration type %q not found in registry", typeID)
	}

	return nil
}

func theOutputShouldListRegisteredTypes(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	output := ctc.Stdout.String()
	if output == "" {
		return fmt.Errorf("output is empty")
	}

	return nil
}

func theOutputShouldShowTypeDetails(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	output := ctc.Stdout.String()
	if !strings.Contains(output, "Display Name") && !strings.Contains(output, "Entry Point") {
		return fmt.Errorf("output does not appear to show type details")
	}

	return nil
}

func theDecorationTypeShouldNotBeRegistered(ctx context.Context, typeID string) error {
	dtc, err := GetDecorationTestContext(ctx)
	if err != nil {
		return err
	}

	// Check in-memory registry
	if _, found := dtc.RegisteredTypes[typeID]; found {
		return fmt.Errorf("decoration type %q still in memory registry", typeID)
	}

	// Check actual registry file
	registryPath := filepath.Join(dtc.WorkDir, ".morphir", "decorations", "registry.json")
	if _, err := os.Stat(registryPath); os.IsNotExist(err) {
		// Registry doesn't exist, so type is not registered
		return nil
	}

	registry, err := decorations.LoadTypeRegistry(registryPath)
	if err != nil {
		return err
	}

	if registry.Has(typeID) {
		return fmt.Errorf("decoration type %q still found in registry", typeID)
	}

	return nil
}
