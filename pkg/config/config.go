// Package config provides a layered configuration system for the Morphir CLI.
//
// The configuration system supports multiple sources with a priority hierarchy:
//  1. Environment variables (highest priority)
//  2. Command-line flags
//  3. .morphir/morphir.user.toml (repo-local, user-specific, gitignored)
//  4. morphir.toml or .morphir/morphir.toml (project config, committed)
//  5. ~/.config/morphir/morphir.toml (global user config)
//  6. /etc/morphir/morphir.toml (system-wide)
//  7. Built-in defaults (lowest priority)
//
// This package follows functional programming principles:
//   - Immutable data structures
//   - Pure functions where possible
//   - Clear separation of concerns
package config

// Config represents the complete, immutable configuration for Morphir tooling.
// All fields are accessible via getter methods to preserve immutability.
type Config struct {
	morphir   MorphirSection
	project   ProjectSection
	workspace WorkspaceSection
	ir        IRSection
	codegen   CodegenSection
	cache     CacheSection
	logging   LoggingSection
	ui        UISection
	tasks     TasksSection
}

// Morphir returns the morphir section configuration.
func (c Config) Morphir() MorphirSection {
	return c.morphir
}

// Project returns the project section configuration.
func (c Config) Project() ProjectSection {
	return c.project
}

// Workspace returns the workspace section configuration.
func (c Config) Workspace() WorkspaceSection {
	return c.workspace
}

// IR returns the IR section configuration.
func (c Config) IR() IRSection {
	return c.ir
}

// Codegen returns the codegen section configuration.
func (c Config) Codegen() CodegenSection {
	return c.codegen
}

// Cache returns the cache section configuration.
func (c Config) Cache() CacheSection {
	return c.cache
}

// Logging returns the logging section configuration.
func (c Config) Logging() LoggingSection {
	return c.logging
}

// UI returns the UI section configuration.
func (c Config) UI() UISection {
	return c.ui
}

// Tasks returns the tasks section configuration.
func (c Config) Tasks() TasksSection {
	return c.tasks
}

// MorphirSection contains core Morphir settings.
type MorphirSection struct {
	version string // Morphir IR version constraint
}

// Version returns the Morphir IR version constraint.
func (s MorphirSection) Version() string {
	return s.version
}

// ProjectSection contains project-related settings for single-project configurations.
type ProjectSection struct {
	name            string   // Flexible project identifier (required)
	version         string   // Project version (optional)
	sourceDirectory string   // Source directory path (required)
	exposedModules  []string // Modules exposed by this project (required)
	modulePrefix    string   // Optional module prefix
}

// Name returns the project identifier.
func (s ProjectSection) Name() string {
	return s.name
}

// Version returns the project version.
func (s ProjectSection) Version() string {
	return s.version
}

// SourceDirectory returns the source directory path.
func (s ProjectSection) SourceDirectory() string {
	return s.sourceDirectory
}

// ExposedModules returns the modules exposed by this project.
// Returns a defensive copy to preserve immutability.
func (s ProjectSection) ExposedModules() []string {
	if len(s.exposedModules) == 0 {
		return nil
	}
	result := make([]string, len(s.exposedModules))
	copy(result, s.exposedModules)
	return result
}

// ModulePrefix returns the optional module prefix.
func (s ProjectSection) ModulePrefix() string {
	return s.modulePrefix
}

// WorkspaceSection contains workspace-related settings.
type WorkspaceSection struct {
	root          string   // Workspace root directory
	outputDir     string   // Output directory for generated artifacts
	members       []string // Glob patterns for workspace members
	exclude       []string // Exclude patterns
	defaultMember string   // Default member for the workspace
}

// Root returns the workspace root directory.
func (s WorkspaceSection) Root() string {
	return s.root
}

// OutputDir returns the output directory for generated artifacts.
func (s WorkspaceSection) OutputDir() string {
	return s.outputDir
}

// Members returns the glob patterns for workspace members.
// Returns a defensive copy to preserve immutability.
func (s WorkspaceSection) Members() []string {
	if len(s.members) == 0 {
		return nil
	}
	result := make([]string, len(s.members))
	copy(result, s.members)
	return result
}

// Exclude returns the exclude patterns for workspace members.
// Returns a defensive copy to preserve immutability.
func (s WorkspaceSection) Exclude() []string {
	if len(s.exclude) == 0 {
		return nil
	}
	result := make([]string, len(s.exclude))
	copy(result, s.exclude)
	return result
}

// DefaultMember returns the default member for the workspace.
func (s WorkspaceSection) DefaultMember() string {
	return s.defaultMember
}

// IRSection contains IR processing settings.
type IRSection struct {
	formatVersion int  // IR format version (e.g., 3)
	strictMode    bool // Enable strict validation
}

// FormatVersion returns the IR format version.
func (s IRSection) FormatVersion() int {
	return s.formatVersion
}

// StrictMode returns whether strict validation is enabled.
func (s IRSection) StrictMode() bool {
	return s.strictMode
}

// CodegenSection contains code generation settings.
type CodegenSection struct {
	targets      []string // Target languages/platforms
	templateDir  string   // Custom template directory
	outputFormat string   // Output format (e.g., "pretty", "compact")
}

// Targets returns the target languages/platforms for code generation.
// Returns a defensive copy to preserve immutability.
func (s CodegenSection) Targets() []string {
	if len(s.targets) == 0 {
		return nil
	}
	result := make([]string, len(s.targets))
	copy(result, s.targets)
	return result
}

// TemplateDir returns the custom template directory.
func (s CodegenSection) TemplateDir() string {
	return s.templateDir
}

// OutputFormat returns the output format.
func (s CodegenSection) OutputFormat() string {
	return s.outputFormat
}

// CacheSection contains caching settings.
type CacheSection struct {
	enabled bool   // Whether caching is enabled
	dir     string // Cache directory path
	maxSize int64  // Maximum cache size in bytes (0 = unlimited)
}

// Enabled returns whether caching is enabled.
func (s CacheSection) Enabled() bool {
	return s.enabled
}

// Dir returns the cache directory path.
func (s CacheSection) Dir() string {
	return s.dir
}

// MaxSize returns the maximum cache size in bytes.
func (s CacheSection) MaxSize() int64 {
	return s.maxSize
}

// LoggingSection contains logging settings.
type LoggingSection struct {
	level  string // Log level (debug, info, warn, error)
	format string // Log format (text, json)
	file   string // Log file path (empty for stderr)
}

// Level returns the log level.
func (s LoggingSection) Level() string {
	return s.level
}

// Format returns the log format.
func (s LoggingSection) Format() string {
	return s.format
}

// File returns the log file path.
func (s LoggingSection) File() string {
	return s.file
}

// UISection contains UI settings.
type UISection struct {
	color       bool   // Enable colored output
	interactive bool   // Enable interactive mode
	theme       string // UI theme name
}

// Color returns whether colored output is enabled.
func (s UISection) Color() bool {
	return s.color
}

// Interactive returns whether interactive mode is enabled.
func (s UISection) Interactive() bool {
	return s.interactive
}

// Theme returns the UI theme name.
func (s UISection) Theme() string {
	return s.theme
}

// Task is the sealed interface for task definitions.
// All implementations must be defined in this package.
// Use type assertions to access type-specific fields:
//
//	switch t := task.(type) {
//	case IntrinsicTask:
//	    action := t.Action()
//	case CommandTask:
//	    cmd := t.Cmd()
//	}
type Task interface {
	DependsOn() []string
	Pre() []string
	Post() []string
	Inputs() []string
	Outputs() []string
	Params() map[string]any
	Env() map[string]string
	Mounts() map[string]string
	isTask() // unexported method seals the interface
}

// taskCommon contains fields shared by all task types.
type taskCommon struct {
	dependsOn []string
	pre       []string
	post      []string
	inputs    []string
	outputs   []string
	params    map[string]any
	env       map[string]string
	mounts    map[string]string
}

// DependsOn returns the task dependencies.
// Returns a defensive copy to preserve immutability.
func (c taskCommon) DependsOn() []string {
	if len(c.dependsOn) == 0 {
		return nil
	}
	result := make([]string, len(c.dependsOn))
	copy(result, c.dependsOn)
	return result
}

// Pre returns the pre-hooks.
// Returns a defensive copy to preserve immutability.
func (c taskCommon) Pre() []string {
	if len(c.pre) == 0 {
		return nil
	}
	result := make([]string, len(c.pre))
	copy(result, c.pre)
	return result
}

// Post returns the post-hooks.
// Returns a defensive copy to preserve immutability.
func (c taskCommon) Post() []string {
	if len(c.post) == 0 {
		return nil
	}
	result := make([]string, len(c.post))
	copy(result, c.post)
	return result
}

// Inputs returns the input globs.
// Returns a defensive copy to preserve immutability.
func (c taskCommon) Inputs() []string {
	if len(c.inputs) == 0 {
		return nil
	}
	result := make([]string, len(c.inputs))
	copy(result, c.inputs)
	return result
}

// Outputs returns the output globs.
// Returns a defensive copy to preserve immutability.
func (c taskCommon) Outputs() []string {
	if len(c.outputs) == 0 {
		return nil
	}
	result := make([]string, len(c.outputs))
	copy(result, c.outputs)
	return result
}

// Params returns the task parameters.
// Returns a defensive copy to preserve immutability.
func (c taskCommon) Params() map[string]any {
	if len(c.params) == 0 {
		return nil
	}
	result := make(map[string]any, len(c.params))
	for k, v := range c.params {
		result[k] = v
	}
	return result
}

// Env returns the environment variables.
// Returns a defensive copy to preserve immutability.
func (c taskCommon) Env() map[string]string {
	if len(c.env) == 0 {
		return nil
	}
	result := make(map[string]string, len(c.env))
	for k, v := range c.env {
		result[k] = v
	}
	return result
}

// Mounts returns the mount permissions.
// Returns a defensive copy to preserve immutability.
func (c taskCommon) Mounts() map[string]string {
	if len(c.mounts) == 0 {
		return nil
	}
	result := make(map[string]string, len(c.mounts))
	for k, v := range c.mounts {
		result[k] = v
	}
	return result
}

// IntrinsicTask represents a built-in Morphir pipeline action.
type IntrinsicTask struct {
	taskCommon
	action string
}

func (IntrinsicTask) isTask() {}

// Action returns the intrinsic action identifier.
func (t IntrinsicTask) Action() string {
	return t.action
}

// CommandTask represents an external command execution.
type CommandTask struct {
	taskCommon
	cmd []string
}

func (CommandTask) isTask() {}

// Cmd returns the command and arguments.
// Returns a defensive copy to preserve immutability.
func (t CommandTask) Cmd() []string {
	if len(t.cmd) == 0 {
		return nil
	}
	result := make([]string, len(t.cmd))
	copy(result, t.cmd)
	return result
}

// TasksSection contains task definitions for the project.
// Tasks can be intrinsic (built-in Morphir actions) or commands (external executables).
type TasksSection struct {
	definitions map[string]Task
}

// Get retrieves a task by name.
// Returns the task and true if found, nil and false otherwise.
func (s TasksSection) Get(name string) (Task, bool) {
	if s.definitions == nil {
		return nil, false
	}
	task, ok := s.definitions[name]
	return task, ok
}

// Names returns a list of all defined task names.
// Returns a defensive copy to preserve immutability.
func (s TasksSection) Names() []string {
	if s.definitions == nil {
		return nil
	}
	names := make([]string, 0, len(s.definitions))
	for name := range s.definitions {
		names = append(names, name)
	}
	return names
}

// Len returns the number of defined tasks.
func (s TasksSection) Len() int {
	return len(s.definitions)
}

// Default returns a Config with sensible default values.
func Default() Config {
	return Config{
		morphir: MorphirSection{
			version: "",
		},
		workspace: WorkspaceSection{
			root:      "",
			outputDir: ".morphir",
		},
		ir: IRSection{
			formatVersion: 3,
			strictMode:    false,
		},
		codegen: CodegenSection{
			targets:      nil,
			templateDir:  "",
			outputFormat: "pretty",
		},
		cache: CacheSection{
			enabled: true,
			dir:     "",
			maxSize: 0,
		},
		logging: LoggingSection{
			level:  "info",
			format: "text",
			file:   "",
		},
		ui: UISection{
			color:       true,
			interactive: true,
			theme:       "default",
		},
		tasks: TasksSection{
			definitions: nil, // No tasks defined by default
		},
	}
}

// SourceInfo describes where a configuration value came from.
type SourceInfo struct {
	name     string // Source name (e.g., "project", "global", "env")
	path     string // File path or environment variable name
	priority int    // Priority level (higher = takes precedence)
	loaded   bool   // Whether the source was successfully loaded
	err      error  // Error if loading failed
}

// Name returns the source name.
func (s SourceInfo) Name() string {
	return s.name
}

// Path returns the file path or environment variable name.
func (s SourceInfo) Path() string {
	return s.path
}

// Priority returns the priority level.
func (s SourceInfo) Priority() int {
	return s.priority
}

// Loaded returns whether the source was successfully loaded.
func (s SourceInfo) Loaded() bool {
	return s.loaded
}

// Error returns any error that occurred while loading this source.
func (s SourceInfo) Error() error {
	return s.err
}

// LoadResult contains the loaded configuration and metadata about its sources.
type LoadResult struct {
	config  Config
	sources []SourceInfo
}

// Config returns the loaded configuration.
func (r LoadResult) Config() Config {
	return r.config
}

// Sources returns information about the configuration sources that were loaded.
// Returns a defensive copy to preserve immutability.
func (r LoadResult) Sources() []SourceInfo {
	if len(r.sources) == 0 {
		return nil
	}
	result := make([]SourceInfo, len(r.sources))
	copy(result, r.sources)
	return result
}

// FromMap creates a Config from a map[string]any.
// This is used internally to convert the loaded configuration map
// to the strongly-typed Config struct.
//
// The map structure should match:
//
//	{
//	  "morphir": { "version": string },
//	  "workspace": { "root": string, "output_dir": string },
//	  "ir": { "format_version": int, "strict_mode": bool },
//	  "codegen": { "targets": []string, "template_dir": string, "output_format": string },
//	  "cache": { "enabled": bool, "dir": string, "max_size": int64 },
//	  "logging": { "level": string, "format": string, "file": string },
//	  "ui": { "color": bool, "interactive": bool, "theme": string },
//	  "tasks": { "<task_name>": { "kind": string, "action": string, "cmd": []string, ... } },
//	}
func FromMap(m map[string]any) Config {
	cfg := Default()

	if m == nil {
		return cfg
	}

	cfg.morphir = morphirFromMap(m, cfg.morphir)
	cfg.project = projectFromMap(m, cfg.project)
	cfg.workspace = workspaceFromMap(m, cfg.workspace)
	cfg.ir = irFromMap(m, cfg.ir)
	cfg.codegen = codegenFromMap(m, cfg.codegen)
	cfg.cache = cacheFromMap(m, cfg.cache)
	cfg.logging = loggingFromMap(m, cfg.logging)
	cfg.ui = uiFromMap(m, cfg.ui)
	cfg.tasks = tasksFromMap(m, cfg.tasks)

	return cfg
}

func morphirFromMap(m map[string]any, def MorphirSection) MorphirSection {
	section, ok := m["morphir"].(map[string]any)
	if !ok {
		return def
	}
	if v, ok := section["version"].(string); ok {
		def.version = v
	}
	return def
}

func projectFromMap(m map[string]any, def ProjectSection) ProjectSection {
	section, ok := m["project"].(map[string]any)
	if !ok {
		return def
	}
	if v, ok := section["name"].(string); ok {
		def.name = v
	}
	if v, ok := section["version"].(string); ok {
		def.version = v
	}
	if v, ok := section["source_directory"].(string); ok {
		def.sourceDirectory = v
	}
	def.exposedModules = getStringSliceFromAny(section["exposed_modules"])
	if v, ok := section["module_prefix"].(string); ok {
		def.modulePrefix = v
	}
	return def
}

func workspaceFromMap(m map[string]any, def WorkspaceSection) WorkspaceSection {
	section, ok := m["workspace"].(map[string]any)
	if !ok {
		return def
	}
	if v, ok := section["root"].(string); ok {
		def.root = v
	}
	if v, ok := section["output_dir"].(string); ok {
		def.outputDir = v
	}
	def.members = getStringSliceFromAny(section["members"])
	def.exclude = getStringSliceFromAny(section["exclude"])
	if v, ok := section["default_member"].(string); ok {
		def.defaultMember = v
	}
	return def
}

func irFromMap(m map[string]any, def IRSection) IRSection {
	section, ok := m["ir"].(map[string]any)
	if !ok {
		return def
	}
	def.formatVersion = getIntFromAny(section["format_version"], def.formatVersion)
	if v, ok := section["strict_mode"].(bool); ok {
		def.strictMode = v
	}
	return def
}

func codegenFromMap(m map[string]any, def CodegenSection) CodegenSection {
	section, ok := m["codegen"].(map[string]any)
	if !ok {
		return def
	}
	def.targets = getStringSliceFromAny(section["targets"])
	if v, ok := section["template_dir"].(string); ok {
		def.templateDir = v
	}
	if v, ok := section["output_format"].(string); ok {
		def.outputFormat = v
	}
	return def
}

func cacheFromMap(m map[string]any, def CacheSection) CacheSection {
	section, ok := m["cache"].(map[string]any)
	if !ok {
		return def
	}
	if v, ok := section["enabled"].(bool); ok {
		def.enabled = v
	}
	if v, ok := section["dir"].(string); ok {
		def.dir = v
	}
	def.maxSize = getInt64FromAny(section["max_size"], def.maxSize)
	return def
}

func loggingFromMap(m map[string]any, def LoggingSection) LoggingSection {
	section, ok := m["logging"].(map[string]any)
	if !ok {
		return def
	}
	if v, ok := section["level"].(string); ok {
		def.level = v
	}
	if v, ok := section["format"].(string); ok {
		def.format = v
	}
	if v, ok := section["file"].(string); ok {
		def.file = v
	}
	return def
}

func uiFromMap(m map[string]any, def UISection) UISection {
	section, ok := m["ui"].(map[string]any)
	if !ok {
		return def
	}
	if v, ok := section["color"].(bool); ok {
		def.color = v
	}
	if v, ok := section["interactive"].(bool); ok {
		def.interactive = v
	}
	if v, ok := section["theme"].(string); ok {
		def.theme = v
	}
	return def
}

func tasksFromMap(m map[string]any, def TasksSection) TasksSection {
	section, ok := m["tasks"].(map[string]any)
	if !ok {
		return def
	}

	definitions := make(map[string]Task)

	for taskName, taskValue := range section {
		taskMap, ok := taskValue.(map[string]any)
		if !ok {
			continue
		}

		task := taskFromMap(taskMap)
		definitions[taskName] = task
	}

	if len(definitions) == 0 {
		return def
	}

	return TasksSection{definitions: definitions}
}

func taskFromMap(m map[string]any) Task {
	// Parse common fields first
	common := taskCommon{
		dependsOn: getStringSliceFromAny(m["depends_on"]),
		pre:       getStringSliceFromAny(m["pre"]),
		post:      getStringSliceFromAny(m["post"]),
		inputs:    getStringSliceFromAny(m["inputs"]),
		outputs:   getStringSliceFromAny(m["outputs"]),
		env:       getStringMapFromAny(m["env"]),
		mounts:    getStringMapFromAny(m["mounts"]),
	}

	// Parse params
	if paramsMap, ok := m["params"].(map[string]any); ok {
		common.params = make(map[string]any, len(paramsMap))
		for k, v := range paramsMap {
			common.params[k] = v
		}
	}

	// Dispatch based on kind
	kind, _ := m["kind"].(string)
	switch kind {
	case "command":
		return CommandTask{
			taskCommon: common,
			cmd:        getStringSliceFromAny(m["cmd"]),
		}
	default:
		// Default to intrinsic (includes explicit "intrinsic" and empty kind)
		action, _ := m["action"].(string)
		return IntrinsicTask{
			taskCommon: common,
			action:     action,
		}
	}
}

// getIntFromAny converts various numeric types to int.
func getIntFromAny(v any, defaultVal int) int {
	switch val := v.(type) {
	case int:
		return val
	case int64:
		return int(val)
	case float64:
		return int(val)
	}
	return defaultVal
}

// getInt64FromAny converts various numeric types to int64.
func getInt64FromAny(v any, defaultVal int64) int64 {
	switch val := v.(type) {
	case int64:
		return val
	case int:
		return int64(val)
	case float64:
		return int64(val)
	}
	return defaultVal
}

// getStringSliceFromAny converts various slice types to []string.
func getStringSliceFromAny(v any) []string {
	switch val := v.(type) {
	case []string:
		if len(val) == 0 {
			return nil
		}
		result := make([]string, len(val))
		copy(result, val)
		return result
	case []any:
		if len(val) == 0 {
			return nil
		}
		result := make([]string, 0, len(val))
		for _, item := range val {
			if s, ok := item.(string); ok {
				result = append(result, s)
			}
		}
		if len(result) == 0 {
			return nil
		}
		return result
	}
	return nil
}

// getStringMapFromAny converts various map types to map[string]string.
func getStringMapFromAny(v any) map[string]string {
	m, ok := v.(map[string]any)
	if !ok {
		return nil
	}
	if len(m) == 0 {
		return nil
	}
	result := make(map[string]string, len(m))
	for k, val := range m {
		if s, ok := val.(string); ok {
			result[k] = s
		}
	}
	if len(result) == 0 {
		return nil
	}
	return result
}

// NewSourceInfo creates a new SourceInfo with the given parameters.
func NewSourceInfo(name, path string, priority int, loaded bool, err error) SourceInfo {
	return SourceInfo{
		name:     name,
		path:     path,
		priority: priority,
		loaded:   loaded,
		err:      err,
	}
}

// NewLoadResult creates a new LoadResult with the given config and sources.
func NewLoadResult(cfg Config, sources []SourceInfo) LoadResult {
	return LoadResult{
		config:  cfg,
		sources: sources,
	}
}
