package steps

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/cucumber/godog"
	"github.com/pelletier/go-toml/v2"
)

// SourceInfo tracks information about a configuration source.
type SourceInfo struct {
	Name     string
	Path     string
	Priority int
	Loaded   bool
	Error    error
}

// ConfigTestContext holds state for config loading BDD scenarios.
type ConfigTestContext struct {
	// TempDir is the temporary directory for test config files.
	TempDir string

	// EnvVars holds environment variables set for the test.
	EnvVars map[string]string

	// OriginalEnv holds original env var values for restoration.
	OriginalEnv map[string]string

	// LoadedConfig is the result of loading configuration.
	LoadedConfig map[string]any

	// LoadedSources tracks which sources were loaded.
	LoadedSources []SourceInfo

	// LastError holds the last error from config loading.
	LastError error
}

// configContextKey is used to store ConfigTestContext in context.Context.
type configContextKey struct{}

// NewConfigTestContext creates a new config test context.
func NewConfigTestContext() *ConfigTestContext {
	return &ConfigTestContext{
		EnvVars:     make(map[string]string),
		OriginalEnv: make(map[string]string),
	}
}

// WithConfigTestContext attaches the config context to the Go context.
func WithConfigTestContext(ctx context.Context, ctc *ConfigTestContext) context.Context {
	return context.WithValue(ctx, configContextKey{}, ctc)
}

// GetConfigTestContext retrieves the config context from the Go context.
func GetConfigTestContext(ctx context.Context) (*ConfigTestContext, error) {
	ctc, ok := ctx.Value(configContextKey{}).(*ConfigTestContext)
	if !ok {
		return nil, fmt.Errorf("config test context not found")
	}
	return ctc, nil
}

// Setup creates a temporary directory for config files.
func (ctc *ConfigTestContext) Setup() error {
	var err error
	ctc.TempDir, err = os.MkdirTemp("", "morphir-config-test-*")
	if err != nil {
		return fmt.Errorf("failed to create temp dir: %w", err)
	}

	// Create subdirectories for different config locations
	dirs := []string{
		"system/morphir",
		"global/morphir",
		"project",
		"project/.morphir",
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(filepath.Join(ctc.TempDir, dir), 0755); err != nil {
			return fmt.Errorf("failed to create %s: %w", dir, err)
		}
	}

	return nil
}

// Cleanup removes the temporary directory and restores environment.
func (ctc *ConfigTestContext) Cleanup() error {
	// Restore original environment variables
	for key, origVal := range ctc.OriginalEnv {
		if origVal == "" {
			os.Unsetenv(key)
		} else {
			os.Setenv(key, origVal)
		}
	}

	// Remove temp directory
	if ctc.TempDir != "" {
		return os.RemoveAll(ctc.TempDir)
	}
	return nil
}

// Reset clears state for a new scenario.
func (ctc *ConfigTestContext) Reset() {
	ctc.LoadedConfig = nil
	ctc.LoadedSources = nil
	ctc.LastError = nil

	// Clean env vars from previous scenario
	for key := range ctc.EnvVars {
		if origVal, ok := ctc.OriginalEnv[key]; ok {
			if origVal == "" {
				os.Unsetenv(key)
			} else {
				os.Setenv(key, origVal)
			}
		} else {
			os.Unsetenv(key)
		}
	}
	ctc.EnvVars = make(map[string]string)
}

// WriteConfigFile writes a config file to the specified location.
func (ctc *ConfigTestContext) WriteConfigFile(location, content string) error {
	var path string
	switch location {
	case "system":
		path = filepath.Join(ctc.TempDir, "system", "morphir", "morphir.toml")
	case "global":
		path = filepath.Join(ctc.TempDir, "global", "morphir", "morphir.toml")
	case "project":
		path = filepath.Join(ctc.TempDir, "project", "morphir.toml")
	case "user":
		path = filepath.Join(ctc.TempDir, "project", ".morphir", "morphir.user.toml")
	default:
		return fmt.Errorf("unknown config location: %s", location)
	}

	return os.WriteFile(path, []byte(content), 0644)
}

// SetEnvVar sets an environment variable for the test.
func (ctc *ConfigTestContext) SetEnvVar(key, value string) {
	// Save original value if we haven't already
	if _, saved := ctc.OriginalEnv[key]; !saved {
		ctc.OriginalEnv[key] = os.Getenv(key)
	}
	ctc.EnvVars[key] = value
	os.Setenv(key, value)
}

// LoadConfig loads configuration from all sources.
func (ctc *ConfigTestContext) LoadConfig() error {
	ctc.LoadedSources = make([]SourceInfo, 0)

	// Start with defaults
	config := defaultValues()
	ctc.LoadedSources = append(ctc.LoadedSources, SourceInfo{
		Name:     "defaults",
		Path:     "(built-in)",
		Priority: 0,
		Loaded:   true,
	})

	// Load from each source in priority order
	sources := []struct {
		name     string
		path     string
		priority int
	}{
		{"system", filepath.Join(ctc.TempDir, "system", "morphir", "morphir.toml"), 100},
		{"global", filepath.Join(ctc.TempDir, "global", "morphir", "morphir.toml"), 200},
		{"project", filepath.Join(ctc.TempDir, "project", "morphir.toml"), 300},
		{"user", filepath.Join(ctc.TempDir, "project", ".morphir", "morphir.user.toml"), 400},
	}

	for _, src := range sources {
		info := SourceInfo{
			Name:     src.name,
			Path:     src.path,
			Priority: src.priority,
		}

		data, err := loadTOMLFile(src.path)
		if err != nil {
			if !errors.Is(err, fs.ErrNotExist) {
				info.Error = err
			}
			info.Loaded = false
		} else if data != nil {
			info.Loaded = true
			config = deepMerge(config, data)
		}

		ctc.LoadedSources = append(ctc.LoadedSources, info)
	}

	// Load environment variables
	envData := loadEnvVars("MORPHIR")
	if envData != nil {
		config = deepMerge(config, envData)
	}
	ctc.LoadedSources = append(ctc.LoadedSources, SourceInfo{
		Name:     "env",
		Path:     "MORPHIR_*",
		Priority: 600,
		Loaded:   envData != nil,
	})

	ctc.LoadedConfig = config
	return nil
}

// RegisterConfigSteps registers all config-related step definitions.
func RegisterConfigSteps(sc *godog.ScenarioContext) {
	// Background/setup steps
	sc.Step(`^a clean config test environment$`, aCleanConfigTestEnvironment)

	// Config file creation steps
	sc.Step(`^no configuration files exist$`, noConfigurationFilesExist)
	sc.Step(`^a project config file with:$`, aProjectConfigFileWith)
	sc.Step(`^a global config file with:$`, aGlobalConfigFileWith)
	sc.Step(`^a system config file with:$`, aSystemConfigFileWith)
	sc.Step(`^a user override config file with:$`, aUserOverrideConfigFileWith)
	sc.Step(`^only a project config file exists with:$`, onlyAProjectConfigFileExistsWith)

	// Environment variable steps
	sc.Step(`^environment variable "([^"]*)" is set to "([^"]*)"$`, environmentVariableIsSetTo)

	// Load steps
	sc.Step(`^I load configuration$`, iLoadConfiguration)
	sc.Step(`^I load configuration with details$`, iLoadConfigurationWithDetails)

	// Assertion steps
	sc.Step(`^the configuration should load successfully$`, theConfigurationShouldLoadSuccessfully)
	sc.Step(`^no errors should be reported$`, noErrorsShouldBeReported)
	sc.Step(`^config "([^"]*)" should be (\d+)$`, configShouldBeInt)
	sc.Step(`^config "([^"]*)" should be "([^"]*)"$`, configShouldBeString)
	sc.Step(`^config "([^"]*)" should be (true|false)$`, configShouldBeBool)
	sc.Step(`^config "([^"]*)" should have (\d+) items$`, configShouldHaveItems)
	sc.Step(`^source "([^"]*)" should be marked as loaded$`, sourceShouldBeMarkedAsLoaded)
	sc.Step(`^source "([^"]*)" should be marked as not loaded$`, sourceShouldBeMarkedAsNotLoaded)

	// Task assertion steps
	sc.Step(`^task "([^"]*)" should exist$`, taskShouldExist)
	sc.Step(`^task "([^"]*)" kind should be "([^"]*)"$`, taskKindShouldBe)
	sc.Step(`^task "([^"]*)" action should be "([^"]*)"$`, taskActionShouldBe)
	sc.Step(`^task "([^"]*)" cmd should have (\d+) items$`, taskCmdShouldHaveItems)
	sc.Step(`^task "([^"]*)" cmd\[(\d+)\] should be "([^"]*)"$`, taskCmdItemShouldBe)
	sc.Step(`^task "([^"]*)" depends_on should have (\d+) items$`, taskDependsOnShouldHaveItems)
	sc.Step(`^task "([^"]*)" depends_on\[(\d+)\] should be "([^"]*)"$`, taskDependsOnItemShouldBe)
	sc.Step(`^task "([^"]*)" pre should have (\d+) items$`, taskPreShouldHaveItems)
	sc.Step(`^task "([^"]*)" post should have (\d+) items$`, taskPostShouldHaveItems)
	sc.Step(`^task "([^"]*)" inputs should have (\d+) items$`, taskInputsShouldHaveItems)
	sc.Step(`^task "([^"]*)" inputs\[(\d+)\] should be "([^"]*)"$`, taskInputsItemShouldBe)
	sc.Step(`^task "([^"]*)" outputs should have (\d+) items$`, taskOutputsShouldHaveItems)
	sc.Step(`^task "([^"]*)" outputs\[(\d+)\] should be "([^"]*)"$`, taskOutputsItemShouldBe)
	sc.Step(`^task "([^"]*)" env "([^"]*)" should be "([^"]*)"$`, taskEnvShouldBe)
	sc.Step(`^task "([^"]*)" mount "([^"]*)" should be "([^"]*)"$`, taskMountShouldBe)
	sc.Step(`^task "([^"]*)" param "([^"]*)" should be "([^"]*)"$`, taskParamShouldBe)
	sc.Step(`^(\d+) tasks should be defined$`, taskCountShouldBe)
}

// Step implementations

func aCleanConfigTestEnvironment(ctx context.Context) (context.Context, error) {
	ctc := NewConfigTestContext()
	if err := ctc.Setup(); err != nil {
		return ctx, err
	}
	return WithConfigTestContext(ctx, ctc), nil
}

func noConfigurationFilesExist(ctx context.Context) error {
	// Config test environment is already clean, no files exist
	return nil
}

func aProjectConfigFileWith(ctx context.Context, content *godog.DocString) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	return ctc.WriteConfigFile("project", content.Content)
}

func aGlobalConfigFileWith(ctx context.Context, content *godog.DocString) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	return ctc.WriteConfigFile("global", content.Content)
}

func aSystemConfigFileWith(ctx context.Context, content *godog.DocString) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	return ctc.WriteConfigFile("system", content.Content)
}

func aUserOverrideConfigFileWith(ctx context.Context, content *godog.DocString) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	return ctc.WriteConfigFile("user", content.Content)
}

func onlyAProjectConfigFileExistsWith(ctx context.Context, content *godog.DocString) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	return ctc.WriteConfigFile("project", content.Content)
}

func environmentVariableIsSetTo(ctx context.Context, key, value string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	ctc.SetEnvVar(key, value)
	return nil
}

func iLoadConfiguration(ctx context.Context) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	ctc.LastError = ctc.LoadConfig()
	return nil
}

func iLoadConfigurationWithDetails(ctx context.Context) error {
	return iLoadConfiguration(ctx)
}

func theConfigurationShouldLoadSuccessfully(ctx context.Context) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	if ctc.LastError != nil {
		return fmt.Errorf("configuration loading failed: %v", ctc.LastError)
	}
	if ctc.LoadedConfig == nil {
		return fmt.Errorf("configuration is nil")
	}
	return nil
}

func noErrorsShouldBeReported(ctx context.Context) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	if ctc.LastError != nil {
		return fmt.Errorf("unexpected error: %v", ctc.LastError)
	}
	return nil
}

func configShouldBeInt(ctx context.Context, path string, expected int) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}

	actual := getInt64(ctc.LoadedConfig, path, -9999)
	if actual != int64(expected) {
		return fmt.Errorf("config %q: expected %d, got %d", path, expected, actual)
	}
	return nil
}

func configShouldBeString(ctx context.Context, path, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}

	actual := getString(ctc.LoadedConfig, path, "")
	if actual != expected {
		return fmt.Errorf("config %q: expected %q, got %q", path, expected, actual)
	}
	return nil
}

func configShouldBeBool(ctx context.Context, path, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}

	expectedBool := expected == "true"
	actual := getBool(ctc.LoadedConfig, path, !expectedBool)
	if actual != expectedBool {
		return fmt.Errorf("config %q: expected %v, got %v", path, expectedBool, actual)
	}
	return nil
}

func configShouldHaveItems(ctx context.Context, path string, count int) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}

	slice := getStringSlice(ctc.LoadedConfig, path, nil)
	if len(slice) != count {
		return fmt.Errorf("config %q: expected %d items, got %d (%v)", path, count, len(slice), slice)
	}
	return nil
}

func sourceShouldBeMarkedAsLoaded(ctx context.Context, sourceName string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}

	for _, src := range ctc.LoadedSources {
		if src.Name == sourceName {
			if src.Loaded {
				return nil
			}
			return fmt.Errorf("source %q was not loaded", sourceName)
		}
	}
	return fmt.Errorf("source %q not found in loaded sources", sourceName)
}

func sourceShouldBeMarkedAsNotLoaded(ctx context.Context, sourceName string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}

	for _, src := range ctc.LoadedSources {
		if src.Name == sourceName {
			if !src.Loaded {
				return nil
			}
			return fmt.Errorf("source %q was unexpectedly loaded", sourceName)
		}
	}
	// Source not in list means it wasn't loaded, which is expected
	return nil
}

// Helper functions for config loading (self-contained for BDD tests)

func defaultValues() map[string]any {
	return map[string]any{
		"morphir": map[string]any{
			"version": "",
		},
		"workspace": map[string]any{
			"root":       "",
			"output_dir": ".morphir",
		},
		"ir": map[string]any{
			"format_version": int64(3),
			"strict_mode":    false,
		},
		"codegen": map[string]any{
			"targets":       []string{},
			"template_dir":  "",
			"output_format": "pretty",
		},
		"cache": map[string]any{
			"enabled":  true,
			"dir":      "",
			"max_size": int64(0),
		},
		"logging": map[string]any{
			"level":  "info",
			"format": "text",
			"file":   "",
		},
		"ui": map[string]any{
			"color":       true,
			"interactive": true,
			"theme":       "default",
		},
	}
}

func loadTOMLFile(path string) (map[string]any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var result map[string]any
	if err := toml.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	return result, nil
}

func loadEnvVars(prefix string) map[string]any {
	result := make(map[string]any)
	prefixWithUnderscore := prefix + "_"

	for _, env := range os.Environ() {
		parts := strings.SplitN(env, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key, value := parts[0], parts[1]
		if !strings.HasPrefix(key, prefixWithUnderscore) {
			continue
		}

		// Remove prefix and convert to config key path
		keyWithoutPrefix := strings.TrimPrefix(key, prefixWithUnderscore)
		keyPath := envKeyToPath(keyWithoutPrefix)

		// Convert value to appropriate type
		typedValue := parseEnvValue(value)

		// Set the value in the nested map
		setNestedValue(result, keyPath, typedValue)
	}

	if len(result) == 0 {
		return nil
	}

	return result
}

func envKeyToPath(key string) []string {
	// Split by double underscore for nesting
	segments := strings.Split(key, "__")
	var path []string
	for _, segment := range segments {
		path = append(path, strings.ToLower(segment))
	}
	return path
}

func parseEnvValue(value string) any {
	// Try boolean
	if b, err := strconv.ParseBool(value); err == nil {
		return b
	}
	// Try integer
	if i, err := strconv.ParseInt(value, 10, 64); err == nil {
		return i
	}
	// Try duration
	if d, err := time.ParseDuration(value); err == nil {
		return d
	}
	return value
}

func setNestedValue(m map[string]any, path []string, value any) {
	if len(path) == 0 {
		return
	}
	if len(path) == 1 {
		m[path[0]] = value
		return
	}
	key := path[0]
	if _, ok := m[key]; !ok {
		m[key] = make(map[string]any)
	}
	if nested, ok := m[key].(map[string]any); ok {
		setNestedValue(nested, path[1:], value)
	}
}

func deepMerge(base, overlay map[string]any) map[string]any {
	if base == nil && overlay == nil {
		return nil
	}
	result := make(map[string]any)

	// Copy base values
	for k, v := range base {
		result[k] = deepCopyValue(v)
	}

	// Merge overlay
	for k, overlayVal := range overlay {
		if overlayVal == nil {
			continue
		}
		baseVal, exists := result[k]
		if !exists {
			result[k] = deepCopyValue(overlayVal)
			continue
		}

		baseMap, baseIsMap := baseVal.(map[string]any)
		overlayMap, overlayIsMap := overlayVal.(map[string]any)

		if baseIsMap && overlayIsMap {
			result[k] = deepMerge(baseMap, overlayMap)
		} else {
			result[k] = deepCopyValue(overlayVal)
		}
	}

	return result
}

func deepCopyValue(v any) any {
	if v == nil {
		return nil
	}
	switch val := v.(type) {
	case map[string]any:
		result := make(map[string]any, len(val))
		for k, v := range val {
			result[k] = deepCopyValue(v)
		}
		return result
	case []any:
		result := make([]any, len(val))
		for i, v := range val {
			result[i] = deepCopyValue(v)
		}
		return result
	case []string:
		result := make([]string, len(val))
		copy(result, val)
		return result
	default:
		return val
	}
}

func getString(m map[string]any, path string, defaultVal string) string {
	val := getNestedValue(m, path)
	if s, ok := val.(string); ok {
		return s
	}
	return defaultVal
}

func getInt64(m map[string]any, path string, defaultVal int64) int64 {
	val := getNestedValue(m, path)
	switch v := val.(type) {
	case int64:
		return v
	case int:
		return int64(v)
	case float64:
		return int64(v)
	}
	return defaultVal
}

func getBool(m map[string]any, path string, defaultVal bool) bool {
	val := getNestedValue(m, path)
	if b, ok := val.(bool); ok {
		return b
	}
	return defaultVal
}

func getStringSlice(m map[string]any, path string, defaultVal []string) []string {
	val := getNestedValue(m, path)
	switch v := val.(type) {
	case []string:
		result := make([]string, len(v))
		copy(result, v)
		return result
	case []any:
		result := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				result = append(result, s)
			}
		}
		return result
	}
	return defaultVal
}

func getNestedValue(m map[string]any, path string) any {
	if m == nil || path == "" {
		return nil
	}

	parts := strings.Split(path, ".")
	current := any(m)

	for _, part := range parts {
		// Handle array access
		if idx := strings.Index(part, "["); idx != -1 {
			arrayKey := part[:idx]
			arrayIdxStr := strings.TrimSuffix(part[idx+1:], "]")
			arrayIdx, _ := strconv.Atoi(arrayIdxStr)

			currentMap, ok := current.(map[string]any)
			if !ok {
				return nil
			}
			arr, ok := currentMap[arrayKey]
			if !ok {
				return nil
			}

			switch a := arr.(type) {
			case []string:
				if arrayIdx < len(a) {
					current = a[arrayIdx]
				} else {
					return nil
				}
			case []any:
				if arrayIdx < len(a) {
					current = a[arrayIdx]
				} else {
					return nil
				}
			default:
				return nil
			}
			continue
		}

		currentMap, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current, ok = currentMap[part]
		if !ok {
			return nil
		}
	}

	return current
}

// Task step implementations

func getTask(ctc *ConfigTestContext, taskName string) (map[string]any, error) {
	tasks, ok := ctc.LoadedConfig["tasks"].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("no tasks section in config")
	}
	task, ok := tasks[taskName].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("task %q not found", taskName)
	}
	return task, nil
}

func taskShouldExist(ctx context.Context, taskName string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	_, err = getTask(ctc, taskName)
	return err
}

func taskKindShouldBe(ctx context.Context, taskName, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	kind, _ := task["kind"].(string)
	if kind != expected {
		return fmt.Errorf("task %q kind: expected %q, got %q", taskName, expected, kind)
	}
	return nil
}

func taskActionShouldBe(ctx context.Context, taskName, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	action, _ := task["action"].(string)
	if action != expected {
		return fmt.Errorf("task %q action: expected %q, got %q", taskName, expected, action)
	}
	return nil
}

func taskCmdShouldHaveItems(ctx context.Context, taskName string, count int) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	cmd := getTaskStringSlice(task, "cmd")
	if len(cmd) != count {
		return fmt.Errorf("task %q cmd: expected %d items, got %d", taskName, count, len(cmd))
	}
	return nil
}

func taskCmdItemShouldBe(ctx context.Context, taskName string, index int, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	cmd := getTaskStringSlice(task, "cmd")
	if index >= len(cmd) {
		return fmt.Errorf("task %q cmd[%d]: index out of range (len=%d)", taskName, index, len(cmd))
	}
	if cmd[index] != expected {
		return fmt.Errorf("task %q cmd[%d]: expected %q, got %q", taskName, index, expected, cmd[index])
	}
	return nil
}

func taskDependsOnShouldHaveItems(ctx context.Context, taskName string, count int) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	deps := getTaskStringSlice(task, "depends_on")
	if len(deps) != count {
		return fmt.Errorf("task %q depends_on: expected %d items, got %d", taskName, count, len(deps))
	}
	return nil
}

func taskDependsOnItemShouldBe(ctx context.Context, taskName string, index int, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	deps := getTaskStringSlice(task, "depends_on")
	if index >= len(deps) {
		return fmt.Errorf("task %q depends_on[%d]: index out of range (len=%d)", taskName, index, len(deps))
	}
	if deps[index] != expected {
		return fmt.Errorf("task %q depends_on[%d]: expected %q, got %q", taskName, index, expected, deps[index])
	}
	return nil
}

func taskPreShouldHaveItems(ctx context.Context, taskName string, count int) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	pre := getTaskStringSlice(task, "pre")
	if len(pre) != count {
		return fmt.Errorf("task %q pre: expected %d items, got %d", taskName, count, len(pre))
	}
	return nil
}

func taskPostShouldHaveItems(ctx context.Context, taskName string, count int) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	post := getTaskStringSlice(task, "post")
	if len(post) != count {
		return fmt.Errorf("task %q post: expected %d items, got %d", taskName, count, len(post))
	}
	return nil
}

func taskInputsShouldHaveItems(ctx context.Context, taskName string, count int) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	inputs := getTaskStringSlice(task, "inputs")
	if len(inputs) != count {
		return fmt.Errorf("task %q inputs: expected %d items, got %d", taskName, count, len(inputs))
	}
	return nil
}

func taskInputsItemShouldBe(ctx context.Context, taskName string, index int, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	inputs := getTaskStringSlice(task, "inputs")
	if index >= len(inputs) {
		return fmt.Errorf("task %q inputs[%d]: index out of range (len=%d)", taskName, index, len(inputs))
	}
	if inputs[index] != expected {
		return fmt.Errorf("task %q inputs[%d]: expected %q, got %q", taskName, index, expected, inputs[index])
	}
	return nil
}

func taskOutputsShouldHaveItems(ctx context.Context, taskName string, count int) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	outputs := getTaskStringSlice(task, "outputs")
	if len(outputs) != count {
		return fmt.Errorf("task %q outputs: expected %d items, got %d", taskName, count, len(outputs))
	}
	return nil
}

func taskOutputsItemShouldBe(ctx context.Context, taskName string, index int, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	outputs := getTaskStringSlice(task, "outputs")
	if index >= len(outputs) {
		return fmt.Errorf("task %q outputs[%d]: index out of range (len=%d)", taskName, index, len(outputs))
	}
	if outputs[index] != expected {
		return fmt.Errorf("task %q outputs[%d]: expected %q, got %q", taskName, index, expected, outputs[index])
	}
	return nil
}

func taskEnvShouldBe(ctx context.Context, taskName, envKey, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	env, ok := task["env"].(map[string]any)
	if !ok {
		return fmt.Errorf("task %q has no env section", taskName)
	}
	value, _ := env[envKey].(string)
	if value != expected {
		return fmt.Errorf("task %q env[%q]: expected %q, got %q", taskName, envKey, expected, value)
	}
	return nil
}

func taskMountShouldBe(ctx context.Context, taskName, mountName, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	mounts, ok := task["mounts"].(map[string]any)
	if !ok {
		return fmt.Errorf("task %q has no mounts section", taskName)
	}
	value, _ := mounts[mountName].(string)
	if value != expected {
		return fmt.Errorf("task %q mount[%q]: expected %q, got %q", taskName, mountName, expected, value)
	}
	return nil
}

func taskParamShouldBe(ctx context.Context, taskName, paramName, expected string) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	task, err := getTask(ctc, taskName)
	if err != nil {
		return err
	}
	params, ok := task["params"].(map[string]any)
	if !ok {
		return fmt.Errorf("task %q has no params section", taskName)
	}
	value := fmt.Sprintf("%v", params[paramName])
	if value != expected {
		return fmt.Errorf("task %q param[%q]: expected %q, got %q", taskName, paramName, expected, value)
	}
	return nil
}

func taskCountShouldBe(ctx context.Context, count int) error {
	ctc, err := GetConfigTestContext(ctx)
	if err != nil {
		return err
	}
	tasks, ok := ctc.LoadedConfig["tasks"].(map[string]any)
	if !ok {
		if count == 0 {
			return nil
		}
		return fmt.Errorf("expected %d tasks, but no tasks section exists", count)
	}
	if len(tasks) != count {
		return fmt.Errorf("expected %d tasks, got %d", count, len(tasks))
	}
	return nil
}

func getTaskStringSlice(task map[string]any, key string) []string {
	val := task[key]
	switch v := val.(type) {
	case []string:
		return v
	case []any:
		result := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				result = append(result, s)
			}
		}
		return result
	}
	return nil
}
