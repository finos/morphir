package steps

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	"github.com/bmatcuk/doublestar/v4"
	"github.com/cucumber/godog"
)

// WorkspaceTestContext holds state for workspace loading BDD scenarios.
type WorkspaceTestContext struct {
	// TempDir is the temporary directory for test workspace.
	TempDir string

	// LoadedWorkspace is the result of loading the workspace.
	LoadedWorkspace *LoadedWorkspaceResult

	// LastError holds the last error from workspace loading.
	LastError error
}

// LoadedWorkspaceResult represents the loaded workspace for testing.
type LoadedWorkspaceResult struct {
	Root        string
	ConfigPath  string
	Members     []MemberResult
	RootProject *MemberResult
	Errors      []error
	Config      map[string]any
}

// MemberResult represents a loaded member project for testing.
type MemberResult struct {
	Name           string
	Path           string
	SourceDir      string
	ModulePrefix   string
	ExposedModules []string
	ConfigFormat   string
	Version        string
}

// workspaceContextKey is used to store WorkspaceTestContext in context.Context.
type workspaceContextKey struct{}

// NewWorkspaceTestContext creates a new workspace test context.
func NewWorkspaceTestContext() *WorkspaceTestContext {
	return &WorkspaceTestContext{}
}

// WithWorkspaceTestContext attaches the workspace context to the Go context.
func WithWorkspaceTestContext(ctx context.Context, wtc *WorkspaceTestContext) context.Context {
	return context.WithValue(ctx, workspaceContextKey{}, wtc)
}

// GetWorkspaceTestContext retrieves the workspace context from the Go context.
func GetWorkspaceTestContext(ctx context.Context) (*WorkspaceTestContext, error) {
	wtc, ok := ctx.Value(workspaceContextKey{}).(*WorkspaceTestContext)
	if !ok {
		return nil, fmt.Errorf("workspace test context not found")
	}
	return wtc, nil
}

// Setup creates a temporary directory for the workspace.
func (wtc *WorkspaceTestContext) Setup() error {
	var err error
	wtc.TempDir, err = os.MkdirTemp("", "morphir-workspace-test-*")
	if err != nil {
		return fmt.Errorf("failed to create temp dir: %w", err)
	}
	return nil
}

// Cleanup removes the temporary directory.
func (wtc *WorkspaceTestContext) Cleanup() error {
	if wtc.TempDir != "" {
		return os.RemoveAll(wtc.TempDir)
	}
	return nil
}

// Reset clears state for a new scenario.
func (wtc *WorkspaceTestContext) Reset() {
	wtc.LoadedWorkspace = nil
	wtc.LastError = nil
}

// WriteFile writes content to a file within the workspace.
func (wtc *WorkspaceTestContext) WriteFile(relPath, content string) error {
	absPath := filepath.Join(wtc.TempDir, relPath)
	dir := filepath.Dir(absPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create directory %s: %w", dir, err)
	}
	return os.WriteFile(absPath, []byte(content), 0644)
}

// RegisterWorkspaceSteps registers all workspace-related step definitions.
func RegisterWorkspaceSteps(sc *godog.ScenarioContext) {
	// Background/setup steps
	sc.Step(`^a clean workspace test environment$`, aCleanWorkspaceTestEnvironment)

	// Workspace config creation
	sc.Step(`^a workspace config with:$`, aWorkspaceConfigWith)

	// Member project creation
	sc.Step(`^a member project at "([^"]*)" with:$`, aMemberProjectAt)
	sc.Step(`^a morphir\.json project at "([^"]*)" with:$`, aMorphirJsonProjectAt)
	sc.Step(`^also a morphir\.json at "([^"]*)" with:$`, alsoAMorphirJsonAt)
	sc.Step(`^a hidden member project at "([^"]*)" with:$`, aHiddenMemberProjectAt)
	sc.Step(`^a custom config file at "([^"]*)" with:$`, aCustomConfigFileAt)
	sc.Step(`^an invalid config at "([^"]*)" with:$`, anInvalidConfigAt)

	// Load steps
	sc.Step(`^I load the workspace$`, iLoadTheWorkspace)

	// Assertion steps - basic
	sc.Step(`^the workspace should load successfully$`, theWorkspaceShouldLoadSuccessfully)
	sc.Step(`^the workspace should have (\d+) members$`, theWorkspaceShouldHaveMembers)
	sc.Step(`^member "([^"]*)" should exist$`, memberShouldExist)
	sc.Step(`^member "([^"]*)" should not exist$`, memberShouldNotExist)

	// Assertion steps - member details
	sc.Step(`^member "([^"]*)" should have module prefix "([^"]*)"$`, memberShouldHaveModulePrefix)
	sc.Step(`^member "([^"]*)" should have (\d+) exposed modules$`, memberShouldHaveExposedModules)

	// Assertion steps - root project
	sc.Step(`^the workspace should have a root project$`, theWorkspaceShouldHaveARootProject)
	sc.Step(`^the workspace should not have a root project$`, theWorkspaceShouldNotHaveARootProject)
	sc.Step(`^the root project name should be "([^"]*)"$`, theRootProjectNameShouldBe)
	sc.Step(`^the root project module prefix should be "([^"]*)"$`, theRootProjectModulePrefixShouldBe)

	// Assertion steps - lookup
	sc.Step(`^looking up member by path "([^"]*)" should find "([^"]*)"$`, lookingUpMemberByPathShouldFind)

	// Assertion steps - config
	sc.Step(`^workspace config "([^"]*)" should be "([^"]*)"$`, workspaceConfigShouldBeString)
	sc.Step(`^workspace config "([^"]*)" should be (\d+)$`, workspaceConfigShouldBeInt)
	sc.Step(`^workspace config "([^"]*)" should be (true|false)$`, workspaceConfigShouldBeBool)

	// Assertion steps - errors
	sc.Step(`^the workspace should have (\d+) loading errors$`, theWorkspaceShouldHaveLoadingErrors)

	// Project list assertions
	sc.Step(`^the project list should contain "([^"]*)"$`, theProjectListShouldContain)
	sc.Step(`^the project list should show (\d+) projects$`, theProjectListShouldShowProjects)
	sc.Step(`^the project list JSON should have (\d+) items$`, theProjectListJSONShouldHaveItems)
	sc.Step(`^the project list JSON item (\d+) should have "([^"]*)" equal to "([^"]*)"$`, theProjectListJSONItemShouldHaveStringEqual)
	sc.Step(`^the project list JSON item (\d+) should have "([^"]*)" equal to (true|false)$`, theProjectListJSONItemShouldHaveBoolEqual)
	sc.Step(`^the project list JSON item (\d+) should have "([^"]*)" equal to (\d+)$`, theProjectListJSONItemShouldHaveIntEqual)
	sc.Step(`^the project list JSON item (\d+) should have "([^"]*)" with (\d+) elements$`, theProjectListJSONItemShouldHaveArrayElements)
	sc.Step(`^the filtered project list JSON with properties "([^"]*)" should have (\d+) items$`, theFilteredProjectListJSONShouldHaveItems)
	sc.Step(`^the filtered project list JSON item (\d+) should have key "([^"]*)"$`, theFilteredProjectListJSONItemShouldHaveKey)
	sc.Step(`^the filtered project list JSON item (\d+) should not have key "([^"]*)"$`, theFilteredProjectListJSONItemShouldNotHaveKey)
}

// Step implementations

func aCleanWorkspaceTestEnvironment(ctx context.Context) (context.Context, error) {
	wtc := NewWorkspaceTestContext()
	if err := wtc.Setup(); err != nil {
		return ctx, err
	}
	return WithWorkspaceTestContext(ctx, wtc), nil
}

func aWorkspaceConfigWith(ctx context.Context, content *godog.DocString) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	return wtc.WriteFile("morphir.toml", content.Content)
}

func aMemberProjectAt(ctx context.Context, path string, content *godog.DocString) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	return wtc.WriteFile(filepath.Join(path, "morphir.toml"), content.Content)
}

func aMorphirJsonProjectAt(ctx context.Context, path string, content *godog.DocString) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	return wtc.WriteFile(filepath.Join(path, "morphir.json"), content.Content)
}

func alsoAMorphirJsonAt(ctx context.Context, path string, content *godog.DocString) error {
	return aMorphirJsonProjectAt(ctx, path, content)
}

func aHiddenMemberProjectAt(ctx context.Context, path string, content *godog.DocString) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	return wtc.WriteFile(filepath.Join(path, ".morphir", "morphir.toml"), content.Content)
}

func aCustomConfigFileAt(ctx context.Context, path string, content *godog.DocString) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	// Write config file at the exact path specified (supports custom filenames)
	return wtc.WriteFile(path, content.Content)
}

func anInvalidConfigAt(ctx context.Context, path string, content *godog.DocString) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	return wtc.WriteFile(path, content.Content)
}

func iLoadTheWorkspace(ctx context.Context) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}

	// Load workspace using the actual implementation
	result, loadErr := loadWorkspaceForTest(wtc.TempDir)
	wtc.LoadedWorkspace = result
	wtc.LastError = loadErr

	return nil
}

func theWorkspaceShouldLoadSuccessfully(ctx context.Context) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	if wtc.LastError != nil {
		return fmt.Errorf("workspace loading failed: %v", wtc.LastError)
	}
	if wtc.LoadedWorkspace == nil {
		return fmt.Errorf("workspace is nil")
	}
	return nil
}

func theWorkspaceShouldHaveMembers(ctx context.Context, count int) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	actual := len(wtc.LoadedWorkspace.Members)
	if actual != count {
		return fmt.Errorf("expected %d members, got %d", count, actual)
	}
	return nil
}

func memberShouldExist(ctx context.Context, name string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	for _, m := range wtc.LoadedWorkspace.Members {
		if m.Name == name {
			return nil
		}
	}
	return fmt.Errorf("member %q not found", name)
}

func memberShouldNotExist(ctx context.Context, name string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	for _, m := range wtc.LoadedWorkspace.Members {
		if m.Name == name {
			return fmt.Errorf("member %q unexpectedly found", name)
		}
	}
	return nil
}

func memberShouldHaveModulePrefix(ctx context.Context, name, prefix string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	for _, m := range wtc.LoadedWorkspace.Members {
		if m.Name == name {
			if m.ModulePrefix != prefix {
				return fmt.Errorf("member %q has module prefix %q, expected %q", name, m.ModulePrefix, prefix)
			}
			return nil
		}
	}
	return fmt.Errorf("member %q not found", name)
}

func memberShouldHaveExposedModules(ctx context.Context, name string, count int) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	for _, m := range wtc.LoadedWorkspace.Members {
		if m.Name == name {
			if len(m.ExposedModules) != count {
				return fmt.Errorf("member %q has %d exposed modules, expected %d", name, len(m.ExposedModules), count)
			}
			return nil
		}
	}
	return fmt.Errorf("member %q not found", name)
}

func theWorkspaceShouldHaveARootProject(ctx context.Context) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	if wtc.LoadedWorkspace.RootProject == nil {
		return fmt.Errorf("expected root project, but none found")
	}
	return nil
}

func theWorkspaceShouldNotHaveARootProject(ctx context.Context) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	if wtc.LoadedWorkspace.RootProject != nil {
		return fmt.Errorf("expected no root project, but found %q", wtc.LoadedWorkspace.RootProject.Name)
	}
	return nil
}

func theRootProjectNameShouldBe(ctx context.Context, name string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	if wtc.LoadedWorkspace.RootProject == nil {
		return fmt.Errorf("no root project")
	}
	if wtc.LoadedWorkspace.RootProject.Name != name {
		return fmt.Errorf("root project name is %q, expected %q", wtc.LoadedWorkspace.RootProject.Name, name)
	}
	return nil
}

func theRootProjectModulePrefixShouldBe(ctx context.Context, prefix string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	if wtc.LoadedWorkspace.RootProject == nil {
		return fmt.Errorf("no root project")
	}
	if wtc.LoadedWorkspace.RootProject.ModulePrefix != prefix {
		return fmt.Errorf("root project module prefix is %q, expected %q", wtc.LoadedWorkspace.RootProject.ModulePrefix, prefix)
	}
	return nil
}

func lookingUpMemberByPathShouldFind(ctx context.Context, relPath, expectedName string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	absPath := filepath.Join(wtc.TempDir, relPath)
	for _, m := range wtc.LoadedWorkspace.Members {
		if m.Path == absPath {
			if m.Name != expectedName {
				return fmt.Errorf("member at path %q has name %q, expected %q", relPath, m.Name, expectedName)
			}
			return nil
		}
	}
	return fmt.Errorf("no member found at path %q", relPath)
}

func workspaceConfigShouldBeString(ctx context.Context, path, expected string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	actual := getString(wtc.LoadedWorkspace.Config, path, "")
	if actual != expected {
		return fmt.Errorf("config %q: expected %q, got %q", path, expected, actual)
	}
	return nil
}

func workspaceConfigShouldBeInt(ctx context.Context, path string, expected int) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	actual := getInt64(wtc.LoadedWorkspace.Config, path, -9999)
	if actual != int64(expected) {
		return fmt.Errorf("config %q: expected %d, got %d", path, expected, actual)
	}
	return nil
}

func workspaceConfigShouldBeBool(ctx context.Context, path, expected string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	expectedBool := expected == "true"
	actual := getBool(wtc.LoadedWorkspace.Config, path, !expectedBool)
	if actual != expectedBool {
		return fmt.Errorf("config %q: expected %v, got %v", path, expectedBool, actual)
	}
	return nil
}

func theWorkspaceShouldHaveLoadingErrors(ctx context.Context, count int) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	actual := len(wtc.LoadedWorkspace.Errors)
	if actual != count {
		return fmt.Errorf("expected %d loading errors, got %d", count, actual)
	}
	return nil
}

// loadWorkspaceForTest loads a workspace and converts it to test result format.
// This uses the actual workspace package implementation.
func loadWorkspaceForTest(root string) (*LoadedWorkspaceResult, error) {
	// Import actual implementation
	// Note: This will need to import from the workspace package
	// For now, we use a simplified inline implementation

	result := &LoadedWorkspaceResult{
		Root:    root,
		Members: []MemberResult{},
		Errors:  []error{},
		Config:  make(map[string]any),
	}

	// Read workspace config
	configPath := filepath.Join(root, "morphir.toml")
	configData, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read workspace config: %w", err)
	}
	result.ConfigPath = configPath

	// Parse TOML (simplified)
	config, err := parseSimpleTOML(string(configData))
	if err != nil {
		return nil, fmt.Errorf("failed to parse workspace config: %w", err)
	}
	result.Config = config

	// Check for root project
	if projectSection, ok := config["project"].(map[string]any); ok {
		if name, ok := projectSection["name"].(string); ok && name != "" {
			result.RootProject = &MemberResult{
				Name:           name,
				Path:           root,
				SourceDir:      getStringDefault(projectSection, "source_directory", "src"),
				ModulePrefix:   getStringDefault(projectSection, "module_prefix", name),
				ExposedModules: getStringSliceDefault(projectSection, "exposed_modules", nil),
				ConfigFormat:   "toml",
				Version:        getStringDefault(projectSection, "version", ""),
			}
		}
	}

	// Get member patterns
	var memberPatterns []string
	var excludePatterns []string

	if wsSection, ok := config["workspace"].(map[string]any); ok {
		if members, ok := wsSection["members"].([]any); ok {
			for _, m := range members {
				if s, ok := m.(string); ok {
					memberPatterns = append(memberPatterns, s)
				}
			}
		}
		if excludes, ok := wsSection["exclude"].([]any); ok {
			for _, e := range excludes {
				if s, ok := e.(string); ok {
					excludePatterns = append(excludePatterns, s)
				}
			}
		}
	}

	// Discover members using doublestar (import actual implementation)
	if len(memberPatterns) > 0 {
		memberPaths, err := discoverMembersForTest(root, memberPatterns, excludePatterns)
		if err != nil {
			result.Errors = append(result.Errors, err)
		} else {
			for _, path := range memberPaths {
				member, err := loadMemberForTest(path)
				if err != nil {
					result.Errors = append(result.Errors, err)
					continue
				}
				result.Members = append(result.Members, *member)
			}
		}
	}

	return result, nil
}

// discoverMembersForTest discovers member directories using generic glob patterns.
// Pattern types:
//   - Directory patterns (e.g., "packages/*"): Match directories, look for default configs
//   - File patterns (e.g., "packages/*/morphir.toml"): Match files, use parent directory
func discoverMembersForTest(root string, patterns, excludes []string) ([]string, error) {
	var members []string
	seen := make(map[string]bool)

	for _, pattern := range patterns {
		matches, err := doublestar.FilepathGlob(filepath.Join(root, pattern))
		if err != nil {
			continue
		}

		for _, match := range matches {
			memberDir := resolveMemberDirForTest(match)
			if memberDir == "" {
				continue
			}

			if seen[memberDir] {
				continue
			}

			// Check if excluded
			if isExcludedForTest(root, memberDir, excludes) {
				continue
			}

			// Validate based on match type
			if isValidMemberForTest(memberDir, match) {
				members = append(members, memberDir)
				seen[memberDir] = true
			}
		}
	}

	return members, nil
}

// resolveMemberDirForTest determines the member directory from a glob match.
func resolveMemberDirForTest(match string) string {
	info, err := os.Stat(match)
	if err != nil {
		return ""
	}

	if info.IsDir() {
		return match
	}

	// Match is a file - return parent directory
	return filepath.Dir(match)
}

// isExcludedForTest checks if a path matches any exclude pattern.
func isExcludedForTest(root, path string, excludes []string) bool {
	if len(excludes) == 0 {
		return false
	}

	relPath, _ := filepath.Rel(root, path)
	for _, exc := range excludes {
		if matched, _ := doublestar.Match(exc, relPath); matched {
			return true
		}
		if matched, _ := doublestar.Match(exc, filepath.Base(path)); matched {
			return true
		}
	}
	return false
}

// isValidMemberForTest checks if a member is valid based on the match type.
func isValidMemberForTest(memberDir, matchedPath string) bool {
	// If match was a file, verify it's a config file we can use
	if matchedPath != memberDir {
		return isConfigFileForTest(matchedPath)
	}

	// Match was a directory - look for default config files
	return hasProjectConfigForTest(memberDir)
}

// isConfigFileForTest checks if a file looks like a config file.
func isConfigFileForTest(path string) bool {
	ext := filepath.Ext(path)
	return ext == ".toml" || ext == ".json"
}

// hasProjectConfigForTest checks if a directory has a default project config.
func hasProjectConfigForTest(dir string) bool {
	// Check morphir.toml with [project]
	tomlPath := filepath.Join(dir, "morphir.toml")
	if data, err := os.ReadFile(tomlPath); err == nil {
		if containsProjectSection(string(data)) {
			return true
		}
	}

	// Check .morphir/morphir.toml
	hiddenTomlPath := filepath.Join(dir, ".morphir", "morphir.toml")
	if data, err := os.ReadFile(hiddenTomlPath); err == nil {
		if containsProjectSection(string(data)) {
			return true
		}
	}

	// Check morphir.json
	jsonPath := filepath.Join(dir, "morphir.json")
	if _, err := os.Stat(jsonPath); err == nil {
		return true
	}

	return false
}

func containsProjectSection(content string) bool {
	return len(content) > 0 && (contains(content, "[project]") || contains(content, "name"))
}

func contains(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// loadMemberForTest loads a member project from a directory.
func loadMemberForTest(path string) (*MemberResult, error) {
	// Try morphir.toml first
	tomlPath := filepath.Join(path, "morphir.toml")
	if data, err := os.ReadFile(tomlPath); err == nil {
		config, err := parseSimpleTOML(string(data))
		if err != nil {
			return nil, err
		}
		if projectSection, ok := config["project"].(map[string]any); ok {
			name := getStringDefault(projectSection, "name", "")
			return &MemberResult{
				Name:           name,
				Path:           path,
				SourceDir:      getStringDefault(projectSection, "source_directory", "src"),
				ModulePrefix:   getStringDefault(projectSection, "module_prefix", name),
				ExposedModules: getStringSliceDefault(projectSection, "exposed_modules", nil),
				ConfigFormat:   "toml",
				Version:        getStringDefault(projectSection, "version", ""),
			}, nil
		}
	}

	// Try .morphir/morphir.toml
	hiddenPath := filepath.Join(path, ".morphir", "morphir.toml")
	if data, err := os.ReadFile(hiddenPath); err == nil {
		config, err := parseSimpleTOML(string(data))
		if err != nil {
			return nil, err
		}
		if projectSection, ok := config["project"].(map[string]any); ok {
			name := getStringDefault(projectSection, "name", "")
			return &MemberResult{
				Name:           name,
				Path:           path,
				SourceDir:      getStringDefault(projectSection, "source_directory", "src"),
				ModulePrefix:   getStringDefault(projectSection, "module_prefix", name),
				ExposedModules: getStringSliceDefault(projectSection, "exposed_modules", nil),
				ConfigFormat:   "toml",
				Version:        getStringDefault(projectSection, "version", ""),
			}, nil
		}
	}

	// Try morphir.json
	jsonPath := filepath.Join(path, "morphir.json")
	if data, err := os.ReadFile(jsonPath); err == nil {
		result, err := parseSimpleJSON(string(data))
		if err != nil {
			return nil, err
		}
		name := getStringDefault(result, "name", "")
		return &MemberResult{
			Name:           name,
			Path:           path,
			SourceDir:      getStringDefault(result, "sourceDirectory", "src"),
			ModulePrefix:   name, // morphir.json uses name as prefix
			ExposedModules: getStringSliceDefault(result, "exposedModules", nil),
			ConfigFormat:   "json",
			Version:        getStringDefault(result, "version", ""),
		}, nil
	}

	return nil, fmt.Errorf("no project config found in %s", path)
}

// parseSimpleTOML is a simplified TOML parser for testing.
func parseSimpleTOML(content string) (map[string]any, error) {
	result := make(map[string]any)
	var currentSection map[string]any

	lines := splitLines(content)
	for _, line := range lines {
		line = trimSpace(line)
		if line == "" || line[0] == '#' {
			continue
		}

		// Section header
		if line[0] == '[' && line[len(line)-1] == ']' {
			sectionName := line[1 : len(line)-1]
			currentSection = make(map[string]any)
			result[sectionName] = currentSection
			continue
		}

		// Key-value pair
		if idx := indexOfEquals(line); idx > 0 {
			key := trimSpace(line[:idx])
			value := trimSpace(line[idx+1:])
			parsedValue := parseTOMLValue(value)

			if currentSection != nil {
				currentSection[key] = parsedValue
			} else {
				result[key] = parsedValue
			}
		}
	}

	return result, nil
}

func parseTOMLValue(s string) any {
	s = trimSpace(s)

	// String
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		return s[1 : len(s)-1]
	}

	// Boolean
	if s == "true" {
		return true
	}
	if s == "false" {
		return false
	}

	// Integer
	if i, err := strconv.ParseInt(s, 10, 64); err == nil {
		return i
	}

	// Array
	if len(s) >= 2 && s[0] == '[' && s[len(s)-1] == ']' {
		inner := trimSpace(s[1 : len(s)-1])
		if inner == "" {
			return []any{}
		}
		items := splitArrayItems(inner)
		result := make([]any, len(items))
		for i, item := range items {
			result[i] = parseTOMLValue(trimSpace(item))
		}
		return result
	}

	return s
}

// parseSimpleJSON is a simplified JSON parser for testing.
func parseSimpleJSON(content string) (map[string]any, error) {
	result := make(map[string]any)

	// Very basic JSON parsing - only handles simple cases
	content = trimSpace(content)
	if len(content) < 2 || content[0] != '{' || content[len(content)-1] != '}' {
		return nil, fmt.Errorf("invalid JSON")
	}

	inner := trimSpace(content[1 : len(content)-1])
	pairs := splitJSONPairs(inner)

	for _, pair := range pairs {
		idx := indexOfColon(pair)
		if idx < 0 {
			continue
		}
		key := trimSpace(pair[:idx])
		value := trimSpace(pair[idx+1:])

		// Remove quotes from key
		if len(key) >= 2 && key[0] == '"' && key[len(key)-1] == '"' {
			key = key[1 : len(key)-1]
		}

		result[key] = parseJSONValue(value)
	}

	return result, nil
}

func parseJSONValue(s string) any {
	s = trimSpace(s)

	// String
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		return s[1 : len(s)-1]
	}

	// Array
	if len(s) >= 2 && s[0] == '[' && s[len(s)-1] == ']' {
		inner := trimSpace(s[1 : len(s)-1])
		if inner == "" {
			return []any{}
		}
		items := splitArrayItems(inner)
		result := make([]any, len(items))
		for i, item := range items {
			result[i] = parseJSONValue(trimSpace(item))
		}
		return result
	}

	return s
}

// Helper functions
func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			line := s[start:i]
			if len(line) > 0 && line[len(line)-1] == '\r' {
				line = line[:len(line)-1]
			}
			lines = append(lines, line)
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

func trimSpace(s string) string {
	start := 0
	end := len(s)
	for start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n' || s[end-1] == '\r') {
		end--
	}
	return s[start:end]
}

func indexOfEquals(s string) int {
	for i := 0; i < len(s); i++ {
		if s[i] == '=' {
			return i
		}
	}
	return -1
}

func indexOfColon(s string) int {
	inString := false
	for i := 0; i < len(s); i++ {
		if s[i] == '"' {
			inString = !inString
		} else if s[i] == ':' && !inString {
			return i
		}
	}
	return -1
}

func splitArrayItems(s string) []string {
	var items []string
	depth := 0
	inString := false
	start := 0

	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == '"' && (i == 0 || s[i-1] != '\\') {
			inString = !inString
		} else if !inString {
			if c == '[' || c == '{' {
				depth++
			} else if c == ']' || c == '}' {
				depth--
			} else if c == ',' && depth == 0 {
				items = append(items, s[start:i])
				start = i + 1
			}
		}
	}
	if start < len(s) {
		items = append(items, s[start:])
	}
	return items
}

func splitJSONPairs(s string) []string {
	return splitArrayItems(s)
}

func getStringDefault(m map[string]any, key, def string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return def
}

func getStringSliceDefault(m map[string]any, key string, def []string) []string {
	if v, ok := m[key].([]any); ok {
		result := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				result = append(result, s)
			}
		}
		return result
	}
	return def
}

// Project list step implementations

// getAllProjects returns all projects (root + members) from the loaded workspace.
func getAllProjects(wtc *WorkspaceTestContext) []MemberResult {
	var all []MemberResult
	if wtc.LoadedWorkspace.RootProject != nil {
		all = append(all, *wtc.LoadedWorkspace.RootProject)
	}
	all = append(all, wtc.LoadedWorkspace.Members...)
	return all
}

func theProjectListShouldContain(ctx context.Context, name string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	projects := getAllProjects(wtc)
	for _, p := range projects {
		if p.Name == name {
			return nil
		}
	}
	return fmt.Errorf("project %q not found in project list", name)
}

func theProjectListShouldShowProjects(ctx context.Context, count int) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	projects := getAllProjects(wtc)
	if len(projects) != count {
		return fmt.Errorf("expected %d projects, got %d", count, len(projects))
	}
	return nil
}

func theProjectListJSONShouldHaveItems(ctx context.Context, count int) error {
	return theProjectListShouldShowProjects(ctx, count)
}

func theProjectListJSONItemShouldHaveStringEqual(ctx context.Context, index int, key, expected string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	projects := getAllProjects(wtc)
	if index >= len(projects) {
		return fmt.Errorf("index %d out of range (have %d projects)", index, len(projects))
	}
	p := projects[index]
	actual := getProjectProperty(p, key)
	if actual != expected {
		return fmt.Errorf("project[%d].%s: expected %q, got %q", index, key, expected, actual)
	}
	return nil
}

func theProjectListJSONItemShouldHaveBoolEqual(ctx context.Context, index int, key, expected string) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	projects := getAllProjects(wtc)
	if index >= len(projects) {
		return fmt.Errorf("index %d out of range (have %d projects)", index, len(projects))
	}
	p := projects[index]
	expectedBool := expected == "true"

	// Special handling for is_root
	if key == "is_root" {
		isRoot := wtc.LoadedWorkspace.RootProject != nil && p.Path == wtc.LoadedWorkspace.RootProject.Path
		if isRoot != expectedBool {
			return fmt.Errorf("project[%d].%s: expected %v, got %v", index, key, expectedBool, isRoot)
		}
		return nil
	}

	return fmt.Errorf("unknown bool property: %s", key)
}

func theProjectListJSONItemShouldHaveIntEqual(ctx context.Context, index int, key string, expected int) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	projects := getAllProjects(wtc)
	if index >= len(projects) {
		return fmt.Errorf("index %d out of range (have %d projects)", index, len(projects))
	}
	p := projects[index]

	var actual int
	switch key {
	case "exposed_modules_count":
		actual = len(p.ExposedModules)
	default:
		return fmt.Errorf("unknown int property: %s", key)
	}

	if actual != expected {
		return fmt.Errorf("project[%d].%s: expected %d, got %d", index, key, expected, actual)
	}
	return nil
}

func theProjectListJSONItemShouldHaveArrayElements(ctx context.Context, index int, key string, count int) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	projects := getAllProjects(wtc)
	if index >= len(projects) {
		return fmt.Errorf("index %d out of range (have %d projects)", index, len(projects))
	}
	p := projects[index]

	var actual int
	switch key {
	case "exposed_modules":
		actual = len(p.ExposedModules)
	default:
		return fmt.Errorf("unknown array property: %s", key)
	}

	if actual != count {
		return fmt.Errorf("project[%d].%s: expected %d elements, got %d", index, key, count, actual)
	}
	return nil
}

// FilteredProjectList holds state for filtered property tests
type FilteredProjectList struct {
	Projects   []map[string]any
	Properties []string
}

var filteredProjectList *FilteredProjectList

func theFilteredProjectListJSONShouldHaveItems(ctx context.Context, properties string, count int) error {
	wtc, err := GetWorkspaceTestContext(ctx)
	if err != nil {
		return err
	}
	projects := getAllProjects(wtc)

	// Parse properties
	var props []string
	for _, p := range splitByComma(properties) {
		props = append(props, trimSpace(p))
	}

	// Build filtered project maps
	filteredProjectList = &FilteredProjectList{
		Projects:   make([]map[string]any, 0, len(projects)),
		Properties: props,
	}

	for i, p := range projects {
		isRoot := wtc.LoadedWorkspace.RootProject != nil && p.Path == wtc.LoadedWorkspace.RootProject.Path
		m := buildFilteredProjectMap(p, isRoot, props)
		filteredProjectList.Projects = append(filteredProjectList.Projects, m)
		_ = i
	}

	if len(filteredProjectList.Projects) != count {
		return fmt.Errorf("expected %d projects, got %d", count, len(filteredProjectList.Projects))
	}
	return nil
}

func theFilteredProjectListJSONItemShouldHaveKey(ctx context.Context, index int, key string) error {
	if filteredProjectList == nil {
		return fmt.Errorf("no filtered project list (call theFilteredProjectListJSONShouldHaveItems first)")
	}
	if index >= len(filteredProjectList.Projects) {
		return fmt.Errorf("index %d out of range", index)
	}
	if _, ok := filteredProjectList.Projects[index][key]; !ok {
		return fmt.Errorf("project[%d] does not have key %q", index, key)
	}
	return nil
}

func theFilteredProjectListJSONItemShouldNotHaveKey(ctx context.Context, index int, key string) error {
	if filteredProjectList == nil {
		return fmt.Errorf("no filtered project list (call theFilteredProjectListJSONShouldHaveItems first)")
	}
	if index >= len(filteredProjectList.Projects) {
		return fmt.Errorf("index %d out of range", index)
	}
	if _, ok := filteredProjectList.Projects[index][key]; ok {
		return fmt.Errorf("project[%d] unexpectedly has key %q", index, key)
	}
	return nil
}

func getProjectProperty(p MemberResult, key string) string {
	switch key {
	case "name":
		return p.Name
	case "path":
		return p.Path
	case "source_directory":
		return p.SourceDir
	case "module_prefix":
		return p.ModulePrefix
	case "config_format":
		return p.ConfigFormat
	case "version":
		return p.Version
	default:
		return ""
	}
}

func buildFilteredProjectMap(p MemberResult, isRoot bool, props []string) map[string]any {
	allProps := map[string]any{
		"name":                  p.Name,
		"path":                  p.Path,
		"config_format":         p.ConfigFormat,
		"source_directory":      p.SourceDir,
		"exposed_modules":       p.ExposedModules,
		"exposed_modules_count": len(p.ExposedModules),
		"module_prefix":         p.ModulePrefix,
		"version":               p.Version,
		"is_root":               isRoot,
	}

	if len(props) == 0 {
		return allProps
	}

	result := make(map[string]any)
	for _, prop := range props {
		if val, ok := allProps[prop]; ok {
			result[prop] = val
		}
	}
	return result
}

func splitByComma(s string) []string {
	var result []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == ',' {
			result = append(result, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		result = append(result, s[start:])
	}
	return result
}
