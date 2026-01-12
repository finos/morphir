package steps

import (
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

// MorphirElmTestContext holds state for morphir-elm BDD scenarios.
type MorphirElmTestContext struct {
	// ExampleProjectPath is the path to the morphir-elm-compat example.
	ExampleProjectPath string

	// ParsedIR holds the parsed morphir-ir.json content.
	ParsedIR *MorphirIR
}

// MorphirIR represents the structure of a morphir-ir.json file.
type MorphirIR struct {
	FormatVersion int           `json:"formatVersion"`
	Distribution  []interface{} `json:"distribution"`
}

// morphirElmContextKey is used to store MorphirElmTestContext in context.Context.
type morphirElmContextKey struct{}

// WithMorphirElmContext attaches the morphir-elm context to the Go context.
func WithMorphirElmContext(ctx context.Context, mec *MorphirElmTestContext) context.Context {
	return context.WithValue(ctx, morphirElmContextKey{}, mec)
}

// GetMorphirElmContext retrieves the morphir-elm context from the Go context.
func GetMorphirElmContext(ctx context.Context) (*MorphirElmTestContext, error) {
	mec, ok := ctx.Value(morphirElmContextKey{}).(*MorphirElmTestContext)
	if !ok {
		return nil, fmt.Errorf("morphir-elm test context not found")
	}
	return mec, nil
}

// RegisterMorphirElmSteps registers step definitions for morphir-elm integration tests.
func RegisterMorphirElmSteps(sc *godog.ScenarioContext) {
	// Background steps
	sc.Step(`^npx is available$`, npxIsAvailable)
	sc.Step(`^the morphir-elm-compat example project exists$`, theMorphirElmCompatProjectExists)

	// Setup steps
	sc.Step(`^I am in the morphir-elm-compat example directory$`, iAmInTheMorphirElmCompatDirectory)
	sc.Step(`^no morphir-ir\.json file exists$`, noMorphirIRFileExists)
	sc.Step(`^a morphir\.json with name "([^"]*)" and exposed modules "([^"]*)"$`, aMorphirJsonWithNameAndModules)

	// Command execution
	sc.Step(`^I run npx morphir-elm make$`, iRunNpxMorphirElmMake)

	// IR validation assertions
	sc.Step(`^the morphir-ir\.json should be valid JSON$`, theMorphirIRShouldBeValidJSON)
	sc.Step(`^the morphir-ir\.json should have format version (\d+)$`, theMorphirIRShouldHaveFormatVersion)
	sc.Step(`^the morphir-ir\.json should contain module "([^"]*)"$`, theMorphirIRShouldContainModule)
	sc.Step(`^the morphir-ir\.json should have package name "([^"]*)"$`, theMorphirIRShouldHavePackageName)
	sc.Step(`^the module "([^"]*)" should have (\d+) types$`, theModuleShouldHaveTypes)
	sc.Step(`^the module "([^"]*)" should have (\d+) values$`, theModuleShouldHaveValues)
}

// Step implementations

func npxIsAvailable(ctx context.Context) error {
	_, err := exec.LookPath("npx")
	if err != nil {
		return fmt.Errorf("npx not found in PATH - ensure Node.js is installed (use mise)")
	}
	return nil
}

func theMorphirElmCompatProjectExists(ctx context.Context) (context.Context, error) {
	examplePath := findExampleProjectPath("morphir-elm-compat")
	if _, err := os.Stat(examplePath); os.IsNotExist(err) {
		return ctx, fmt.Errorf("morphir-elm-compat example project not found at %s", examplePath)
	}

	mec := &MorphirElmTestContext{
		ExampleProjectPath: examplePath,
	}
	return WithMorphirElmContext(ctx, mec), nil
}

func iAmInTheMorphirElmCompatDirectory(ctx context.Context) error {
	mec, err := GetMorphirElmContext(ctx)
	if err != nil {
		return err
	}

	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	ctc.WorkDir = mec.ExampleProjectPath
	return nil
}

func noMorphirIRFileExists(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	irPath := filepath.Join(ctc.WorkDir, "morphir-ir.json")
	os.Remove(irPath)

	hashesPath := filepath.Join(ctc.WorkDir, "morphir-hashes.json")
	os.Remove(hashesPath)

	return nil
}

func aMorphirJsonWithNameAndModules(ctx context.Context, name, modules string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	moduleList := strings.Split(modules, ",")
	for i, m := range moduleList {
		moduleList[i] = fmt.Sprintf(`"%s"`, strings.TrimSpace(m))
	}

	content := fmt.Sprintf(`{
    "name": "%s",
    "sourceDirectory": "src",
    "exposedModules": [%s]
}`, name, strings.Join(moduleList, ", "))

	morphirJsonPath := filepath.Join(ctc.WorkDir, "morphir.json")
	return os.WriteFile(morphirJsonPath, []byte(content), 0644)
}

func iRunNpxMorphirElmMake(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	cmd := exec.Command("npx", "-y", "morphir-elm", "make")
	cmd.Dir = ctc.WorkDir
	cmd.Env = append(os.Environ(), "NODE_OPTIONS=--max-old-space-size=4096")
	cmd.Stdout = &ctc.Stdout
	cmd.Stderr = &ctc.Stderr

	err = cmd.Run()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			ctc.ExitCode = exitErr.ExitCode()
		} else {
			ctc.ExitCode = 1
		}
		ctc.LastError = err
	} else {
		ctc.ExitCode = 0
	}

	return nil
}

func theMorphirIRShouldBeValidJSON(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	mec, err := GetMorphirElmContext(ctx)
	if err != nil {
		return err
	}

	irPath := filepath.Join(ctc.WorkDir, "morphir-ir.json")
	content, err := os.ReadFile(irPath)
	if err != nil {
		return fmt.Errorf("failed to read morphir-ir.json: %w", err)
	}

	var ir MorphirIR
	if err := json.Unmarshal(content, &ir); err != nil {
		return fmt.Errorf("morphir-ir.json is not valid JSON: %w", err)
	}

	mec.ParsedIR = &ir
	return nil
}

func theMorphirIRShouldHaveFormatVersion(ctx context.Context, version int) error {
	mec, err := GetMorphirElmContext(ctx)
	if err != nil {
		return err
	}

	if mec.ParsedIR == nil {
		if err := theMorphirIRShouldBeValidJSON(ctx); err != nil {
			return err
		}
	}

	if mec.ParsedIR.FormatVersion != version {
		return fmt.Errorf("expected format version %d, got %d", version, mec.ParsedIR.FormatVersion)
	}
	return nil
}

func theMorphirIRShouldContainModule(ctx context.Context, moduleName string) error {
	mec, err := GetMorphirElmContext(ctx)
	if err != nil {
		return err
	}

	if mec.ParsedIR == nil {
		if err := theMorphirIRShouldBeValidJSON(ctx); err != nil {
			return err
		}
	}

	modules := extractModuleNames(mec.ParsedIR)
	for _, m := range modules {
		if m == moduleName {
			return nil
		}
	}

	return fmt.Errorf("module %q not found in IR, available modules: %v", moduleName, modules)
}

func theMorphirIRShouldHavePackageName(ctx context.Context, packageName string) error {
	mec, err := GetMorphirElmContext(ctx)
	if err != nil {
		return err
	}

	if mec.ParsedIR == nil {
		if err := theMorphirIRShouldBeValidJSON(ctx); err != nil {
			return err
		}
	}

	actualName := extractPackageName(mec.ParsedIR)
	if actualName != packageName {
		return fmt.Errorf("expected package name %q, got %q", packageName, actualName)
	}
	return nil
}

func theModuleShouldHaveTypes(ctx context.Context, moduleName string, expectedCount int) error {
	mec, err := GetMorphirElmContext(ctx)
	if err != nil {
		return err
	}

	if mec.ParsedIR == nil {
		if err := theMorphirIRShouldBeValidJSON(ctx); err != nil {
			return err
		}
	}

	typeCount := countModuleTypes(mec.ParsedIR, moduleName)
	if typeCount != expectedCount {
		return fmt.Errorf("module %q: expected %d types, got %d", moduleName, expectedCount, typeCount)
	}
	return nil
}

func theModuleShouldHaveValues(ctx context.Context, moduleName string, expectedCount int) error {
	mec, err := GetMorphirElmContext(ctx)
	if err != nil {
		return err
	}

	if mec.ParsedIR == nil {
		if err := theMorphirIRShouldBeValidJSON(ctx); err != nil {
			return err
		}
	}

	valueCount := countModuleValues(mec.ParsedIR, moduleName)
	if valueCount != expectedCount {
		return fmt.Errorf("module %q: expected %d values, got %d", moduleName, expectedCount, valueCount)
	}
	return nil
}

// Helper functions

func findExampleProjectPath(name string) string {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		return ""
	}

	// Navigate from tests/bdd/steps to examples/
	stepsDir := filepath.Dir(filename)
	repoRoot := filepath.Join(stepsDir, "..", "..", "..")
	examplePath := filepath.Join(repoRoot, "examples", name)

	absPath, err := filepath.Abs(examplePath)
	if err != nil {
		return examplePath
	}
	return absPath
}

func extractModuleNames(ir *MorphirIR) []string {
	if len(ir.Distribution) < 4 {
		return nil
	}

	pkgDef, ok := ir.Distribution[3].(map[string]interface{})
	if !ok {
		return nil
	}

	modulesRaw, ok := pkgDef["modules"].([]interface{})
	if !ok {
		return nil
	}

	var names []string
	for _, m := range modulesRaw {
		moduleArr, ok := m.([]interface{})
		if !ok || len(moduleArr) < 1 {
			continue
		}

		nameArr, ok := moduleArr[0].([]interface{})
		if !ok || len(nameArr) < 1 {
			continue
		}

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
			names = append(names, nameParts[len(nameParts)-1])
		}
	}

	return names
}

func extractPackageName(ir *MorphirIR) string {
	if len(ir.Distribution) < 2 {
		return ""
	}

	pkgNameRaw, ok := ir.Distribution[1].([]interface{})
	if !ok {
		return ""
	}

	var parts []string
	for _, segment := range pkgNameRaw {
		segArr, ok := segment.([]interface{})
		if !ok {
			continue
		}
		for _, part := range segArr {
			if s, ok := part.(string); ok {
				parts = append(parts, s)
			}
		}
	}

	return strings.Join(parts, ".")
}

func countModuleTypes(ir *MorphirIR, moduleName string) int {
	module := findModule(ir, moduleName)
	if module == nil {
		return 0
	}

	moduleDef, ok := module["value"].(map[string]interface{})
	if !ok {
		return 0
	}

	types, ok := moduleDef["types"].([]interface{})
	if !ok {
		return 0
	}

	return len(types)
}

func countModuleValues(ir *MorphirIR, moduleName string) int {
	module := findModule(ir, moduleName)
	if module == nil {
		return 0
	}

	moduleDef, ok := module["value"].(map[string]interface{})
	if !ok {
		return 0
	}

	values, ok := moduleDef["values"].([]interface{})
	if !ok {
		return 0
	}

	return len(values)
}

func findModule(ir *MorphirIR, moduleName string) map[string]interface{} {
	if len(ir.Distribution) < 4 {
		return nil
	}

	pkgDef, ok := ir.Distribution[3].(map[string]interface{})
	if !ok {
		return nil
	}

	modulesRaw, ok := pkgDef["modules"].([]interface{})
	if !ok {
		return nil
	}

	for _, m := range modulesRaw {
		moduleArr, ok := m.([]interface{})
		if !ok || len(moduleArr) < 2 {
			continue
		}

		nameArr, ok := moduleArr[0].([]interface{})
		if !ok || len(nameArr) < 1 {
			continue
		}

		// Extract last part of module name
		var lastPart string
		for _, seg := range nameArr {
			segArr, ok := seg.([]interface{})
			if !ok {
				continue
			}
			for _, part := range segArr {
				if s, ok := part.(string); ok {
					lastPart = s
				}
			}
		}

		if lastPart == moduleName {
			if moduleDef, ok := moduleArr[1].(map[string]interface{}); ok {
				return moduleDef
			}
		}
	}

	return nil
}
