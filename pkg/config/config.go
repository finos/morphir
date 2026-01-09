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

import (
	"github.com/finos/morphir/pkg/bindings/typemap"
)

// Config represents the complete, immutable configuration for Morphir tooling.
// All fields are accessible via getter methods to preserve immutability.
type Config struct {
	morphir    MorphirSection
	project    ProjectSection
	workspace  WorkspaceSection
	ir         IRSection
	codegen    CodegenSection
	cache      CacheSection
	logging    LoggingSection
	ui         UISection
	tasks      TasksSection
	workflows  WorkflowsSection
	bindings   BindingsSection
	toolchains ToolchainsSection
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

// Workflows returns the workflows section configuration.
func (c Config) Workflows() WorkflowsSection {
	return c.workflows
}

// Bindings returns the bindings section configuration.
func (c Config) Bindings() BindingsSection {
	return c.bindings
}

// Toolchains returns the toolchains section configuration.
func (c Config) Toolchains() ToolchainsSection {
	return c.toolchains
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

// WorkflowsSection contains workflow definitions for the project.
// Workflows define staged orchestration of targets.
type WorkflowsSection struct {
	definitions map[string]WorkflowConfig
}

// Get retrieves a workflow configuration by name.
// Returns the workflow config and true if found, otherwise returns an empty
// config and false.
func (s WorkflowsSection) Get(name string) (WorkflowConfig, bool) {
	if s.definitions == nil {
		return WorkflowConfig{}, false
	}
	workflow, ok := s.definitions[name]
	return workflow, ok
}

// Names returns a list of all defined workflow names.
// Returns a defensive copy to preserve immutability.
func (s WorkflowsSection) Names() []string {
	if s.definitions == nil {
		return nil
	}
	names := make([]string, 0, len(s.definitions))
	for name := range s.definitions {
		names = append(names, name)
	}
	return names
}

// Len returns the number of defined workflows.
func (s WorkflowsSection) Len() int {
	return len(s.definitions)
}

// WorkflowConfig represents a workflow definition.
//
// Example configuration in morphir.toml:
//
//	[workflows.build]
//	description = "Standard build workflow"
//	stages = [
//	  { name = "frontend", targets = ["make"] },
//	  { name = "backend", targets = ["gen:scala"] },
//	]
type WorkflowConfig struct {
	name        string
	description string
	extends     string
	stages      []WorkflowStageConfig
}

// Name returns the workflow name.
func (c WorkflowConfig) Name() string {
	return c.name
}

// Description returns the workflow description.
func (c WorkflowConfig) Description() string {
	return c.description
}

// Extends returns the name of the base workflow.
func (c WorkflowConfig) Extends() string {
	return c.extends
}

// Stages returns the workflow stages.
func (c WorkflowConfig) Stages() []WorkflowStageConfig {
	if len(c.stages) == 0 {
		return nil
	}
	result := make([]WorkflowStageConfig, len(c.stages))
	copy(result, c.stages)
	return result
}

// WorkflowStageConfig represents a single workflow stage.
type WorkflowStageConfig struct {
	name      string
	targets   []string
	parallel  bool
	condition string
}

// Name returns the stage name.
func (c WorkflowStageConfig) Name() string {
	return c.name
}

// Targets returns the stage target list.
func (c WorkflowStageConfig) Targets() []string {
	if len(c.targets) == 0 {
		return nil
	}
	result := make([]string, len(c.targets))
	copy(result, c.targets)
	return result
}

// Parallel returns whether the stage can run in parallel.
func (c WorkflowStageConfig) Parallel() bool {
	return c.parallel
}

// Condition returns the stage condition expression.
func (c WorkflowStageConfig) Condition() string {
	return c.condition
}

// BindingsSection contains type mapping configuration for external bindings.
// Each binding (WIT, Protobuf, JSON Schema, etc.) can have its own type mappings.
type BindingsSection struct {
	wit      typemap.TypeMappingConfig
	protobuf typemap.TypeMappingConfig
	json     typemap.TypeMappingConfig
}

// WIT returns the WIT binding type mapping configuration.
func (s BindingsSection) WIT() typemap.TypeMappingConfig {
	return s.wit
}

// Protobuf returns the Protocol Buffers binding type mapping configuration.
func (s BindingsSection) Protobuf() typemap.TypeMappingConfig {
	return s.protobuf
}

// JSON returns the JSON Schema binding type mapping configuration.
func (s BindingsSection) JSON() typemap.TypeMappingConfig {
	return s.json
}

// IsEmpty returns true if no binding configurations are defined.
func (s BindingsSection) IsEmpty() bool {
	return s.wit.IsEmpty() && s.protobuf.IsEmpty() && s.json.IsEmpty()
}

// ToolchainsSection contains toolchain definitions for the project.
// Toolchains define how to acquire and execute external tools or native
// implementations for tasks like compilation, code generation, and validation.
//
// Example usage:
//
//	cfg := config.Load()
//	tc, ok := cfg.Toolchains().Get("morphir-elm")
//	if ok {
//	    version := tc.Version()
//	    tasks := tc.Tasks()
//	}
type ToolchainsSection struct {
	definitions map[string]ToolchainConfig
}

// Get retrieves a toolchain configuration by name.
// Returns the toolchain config and true if found, otherwise returns an empty
// config and false.
func (s ToolchainsSection) Get(name string) (ToolchainConfig, bool) {
	if s.definitions == nil {
		return ToolchainConfig{}, false
	}
	tc, ok := s.definitions[name]
	return tc, ok
}

// Names returns a list of all defined toolchain names.
func (s ToolchainsSection) Names() []string {
	if s.definitions == nil {
		return nil
	}
	names := make([]string, 0, len(s.definitions))
	for name := range s.definitions {
		names = append(names, name)
	}
	return names
}

// Len returns the number of defined toolchains.
func (s ToolchainsSection) Len() int {
	return len(s.definitions)
}

// ToolchainConfig represents the configuration for a toolchain.
// A toolchain can be either native (in-process Go implementation) or external
// (process-based tool like morphir-elm).
//
// Example configuration in morphir.toml:
//
//	[toolchain.morphir-elm]
//	version = "2.90.0"
//	timeout = "5m"
//
//	[toolchain.morphir-elm.acquire]
//	backend = "path"
//	executable = "morphir-elm"
//
//	[toolchain.morphir-elm.tasks.make]
//	exec = "morphir-elm"
//	args = ["make", "-o", "{outputs.ir}"]
//	fulfills = ["make"]
type ToolchainConfig struct {
	name       string
	version    string
	acquire    AcquireConfig
	env        map[string]string
	workingDir string
	timeout    string // Duration string like "5m"
	tasks      map[string]ToolchainTaskConfig
}

// Name returns the toolchain name.
func (c ToolchainConfig) Name() string {
	return c.name
}

// Version returns the toolchain version.
func (c ToolchainConfig) Version() string {
	return c.version
}

// Acquire returns the acquisition configuration.
func (c ToolchainConfig) Acquire() AcquireConfig {
	return c.acquire
}

// Env returns the environment variables.
func (c ToolchainConfig) Env() map[string]string {
	if len(c.env) == 0 {
		return nil
	}
	result := make(map[string]string, len(c.env))
	for k, v := range c.env {
		result[k] = v
	}
	return result
}

// WorkingDir returns the working directory.
func (c ToolchainConfig) WorkingDir() string {
	return c.workingDir
}

// Timeout returns the timeout string.
func (c ToolchainConfig) Timeout() string {
	return c.timeout
}

// Tasks returns the task configurations.
func (c ToolchainConfig) Tasks() map[string]ToolchainTaskConfig {
	if len(c.tasks) == 0 {
		return nil
	}
	result := make(map[string]ToolchainTaskConfig, len(c.tasks))
	for k, v := range c.tasks {
		result[k] = v
	}
	return result
}

// AcquireConfig specifies how to acquire a toolchain.
// Supported backends include:
//   - "path": Tool is already on PATH
//   - "npx": Run via npx (planned)
//   - "npm": Install via npm (planned)
//   - "mise": Manage via mise (planned)
//
// Example:
//
//	[toolchain.morphir-elm.acquire]
//	backend = "path"
//	executable = "morphir-elm"
type AcquireConfig struct {
	backend    string
	packageVal string // "package" is a reserved keyword in Go
	version    string
	executable string
}

// Backend returns the acquisition backend.
func (c AcquireConfig) Backend() string {
	return c.backend
}

// Package returns the package name.
func (c AcquireConfig) Package() string {
	return c.packageVal
}

// Version returns the version constraint.
func (c AcquireConfig) Version() string {
	return c.version
}

// Executable returns the executable name.
func (c AcquireConfig) Executable() string {
	return c.executable
}

// ToolchainTaskConfig represents a task in a toolchain definition.
// Tasks are concrete implementations that execute external commands or
// native Go code to perform operations like compilation or code generation.
//
// Example:
//
//	[toolchain.morphir-elm.tasks.make]
//	exec = "morphir-elm"
//	args = ["make", "-o", "{outputs.ir}"]
//	fulfills = ["make"]
//	variants = ["Scala", "TypeScript"]
//
//	[toolchain.morphir-elm.tasks.make.inputs]
//	files = ["elm.json", "src/**/*.elm"]
//
//	[toolchain.morphir-elm.tasks.make.outputs.ir]
//	path = "morphir-ir.json"
//	type = "morphir-ir"
type ToolchainTaskConfig struct {
	exec     string
	args     []string
	inputs   InputsConfig
	outputs  map[string]OutputConfig
	fulfills []string
	variants []string
	env      map[string]string
}

// Exec returns the executable name.
func (c ToolchainTaskConfig) Exec() string {
	return c.exec
}

// Args returns the command arguments.
func (c ToolchainTaskConfig) Args() []string {
	if len(c.args) == 0 {
		return nil
	}
	result := make([]string, len(c.args))
	copy(result, c.args)
	return result
}

// Inputs returns the inputs configuration.
func (c ToolchainTaskConfig) Inputs() InputsConfig {
	return c.inputs
}

// Outputs returns the outputs configuration.
func (c ToolchainTaskConfig) Outputs() map[string]OutputConfig {
	if len(c.outputs) == 0 {
		return nil
	}
	result := make(map[string]OutputConfig, len(c.outputs))
	for k, v := range c.outputs {
		result[k] = v
	}
	return result
}

// Fulfills returns the list of targets this task fulfills.
func (c ToolchainTaskConfig) Fulfills() []string {
	if len(c.fulfills) == 0 {
		return nil
	}
	result := make([]string, len(c.fulfills))
	copy(result, c.fulfills)
	return result
}

// Variants returns the supported variants.
func (c ToolchainTaskConfig) Variants() []string {
	if len(c.variants) == 0 {
		return nil
	}
	result := make([]string, len(c.variants))
	copy(result, c.variants)
	return result
}

// Env returns the environment variables.
func (c ToolchainTaskConfig) Env() map[string]string {
	if len(c.env) == 0 {
		return nil
	}
	result := make(map[string]string, len(c.env))
	for k, v := range c.env {
		result[k] = v
	}
	return result
}

// InputsConfig specifies task inputs.
// Inputs can be either file patterns or references to artifacts produced
// by other tasks.
//
// Example:
//
//	[toolchain.morphir-elm.tasks.gen.inputs]
//	files = ["src/**/*.elm"]
//	artifacts = { ir = "@morphir-elm/make:ir" }
type InputsConfig struct {
	files     []string
	artifacts map[string]string
}

// Files returns file glob patterns.
func (c InputsConfig) Files() []string {
	if len(c.files) == 0 {
		return nil
	}
	result := make([]string, len(c.files))
	copy(result, c.files)
	return result
}

// Artifacts returns artifact references.
func (c InputsConfig) Artifacts() map[string]string {
	if len(c.artifacts) == 0 {
		return nil
	}
	result := make(map[string]string, len(c.artifacts))
	for k, v := range c.artifacts {
		result[k] = v
	}
	return result
}

// OutputConfig specifies a task output.
// Outputs are written to .morphir/out/{toolchain}/{task}/ directory.
//
// Example:
//
//	[toolchain.morphir-elm.tasks.make.outputs.ir]
//	path = "morphir-ir.json"
//	type = "morphir-ir"
type OutputConfig struct {
	path    string
	typeVal string // "type" is a reserved keyword in Go
}

// Path returns the output path.
func (c OutputConfig) Path() string {
	return c.path
}

// Type returns the output type.
func (c OutputConfig) Type() string {
	return c.typeVal
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
		workflows: WorkflowsSection{
			definitions: nil, // No workflows defined by default
		},
		bindings: BindingsSection{}, // Empty by default; bindings use their built-in defaults
		toolchains: ToolchainsSection{
			definitions: nil, // No toolchains defined by default
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
//	  "workflows": { "<workflow_name>": { "description": string, "extends": string, "stages": [...] } },
//	  "bindings": { "wit": { "primitives": [...], "containers": [...] }, ... },
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
	cfg.workflows = workflowsFromMap(m, cfg.workflows)
	cfg.bindings = bindingsFromMap(m, cfg.bindings)
	cfg.toolchains = toolchainsFromMap(m, cfg.toolchains)

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

// workflowsFromMap parses workflow configurations from a map.
func workflowsFromMap(m map[string]any, def WorkflowsSection) WorkflowsSection {
	section, ok := m["workflows"].(map[string]any)
	if !ok {
		return def
	}

	definitions := make(map[string]WorkflowConfig)
	for workflowName, workflowValue := range section {
		workflowMap, ok := workflowValue.(map[string]any)
		if !ok {
			continue
		}
		definitions[workflowName] = workflowConfigFromMap(workflowName, workflowMap)
	}

	if len(definitions) == 0 {
		return def
	}

	return WorkflowsSection{definitions: definitions}
}

// workflowConfigFromMap parses a WorkflowConfig from a map.
func workflowConfigFromMap(name string, m map[string]any) WorkflowConfig {
	cfg := WorkflowConfig{name: name}
	if description, ok := m["description"].(string); ok {
		cfg.description = description
	}
	if extends, ok := m["extends"].(string); ok {
		cfg.extends = extends
	}
	if stagesVal, ok := m["stages"]; ok {
		cfg.stages = workflowStagesFromAny(stagesVal)
	}
	return cfg
}

func workflowStagesFromAny(v any) []WorkflowStageConfig {
	switch val := v.(type) {
	case []WorkflowStageConfig:
		if len(val) == 0 {
			return nil
		}
		result := make([]WorkflowStageConfig, len(val))
		copy(result, val)
		return result
	case []any:
		if len(val) == 0 {
			return nil
		}
		stages := make([]WorkflowStageConfig, 0, len(val))
		for _, item := range val {
			stageMap, ok := item.(map[string]any)
			if !ok {
				continue
			}
			stage := workflowStageFromMap(stageMap)
			if stage.name == "" && len(stage.targets) == 0 && !stage.parallel && stage.condition == "" {
				continue
			}
			stages = append(stages, stage)
		}
		if len(stages) == 0 {
			return nil
		}
		return stages
	}
	return nil
}

func workflowStageFromMap(m map[string]any) WorkflowStageConfig {
	cfg := WorkflowStageConfig{}
	if name, ok := m["name"].(string); ok {
		cfg.name = name
	}
	cfg.targets = getStringSliceFromAny(m["targets"])
	if parallel, ok := m["parallel"].(bool); ok {
		cfg.parallel = parallel
	}
	if condition, ok := m["condition"].(string); ok {
		cfg.condition = condition
	}
	return cfg
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

// bindingsFromMap parses binding configurations from a map.
func bindingsFromMap(m map[string]any, def BindingsSection) BindingsSection {
	section, ok := m["bindings"].(map[string]any)
	if !ok {
		return def
	}

	if witSection, ok := section["wit"].(map[string]any); ok {
		def.wit = typeMappingConfigFromMap(witSection)
	}
	if protobufSection, ok := section["protobuf"].(map[string]any); ok {
		def.protobuf = typeMappingConfigFromMap(protobufSection)
	}
	if jsonSection, ok := section["json"].(map[string]any); ok {
		def.json = typeMappingConfigFromMap(jsonSection)
	}

	return def
}

// typeMappingConfigFromMap parses a TypeMappingConfig from a map.
func typeMappingConfigFromMap(m map[string]any) typemap.TypeMappingConfig {
	cfg := typemap.TypeMappingConfig{}

	// Parse primitives array
	if primitives, ok := m["primitives"].([]any); ok {
		for _, item := range primitives {
			if prim, ok := item.(map[string]any); ok {
				cfg.Primitives = append(cfg.Primitives, primitiveMappingFromMap(prim))
			}
		}
	}

	// Parse containers array
	if containers, ok := m["containers"].([]any); ok {
		for _, item := range containers {
			if cont, ok := item.(map[string]any); ok {
				cfg.Containers = append(cfg.Containers, containerMappingFromMap(cont))
			}
		}
	}

	return cfg
}

// primitiveMappingFromMap parses a PrimitiveMappingConfig from a map.
func primitiveMappingFromMap(m map[string]any) typemap.PrimitiveMappingConfig {
	cfg := typemap.PrimitiveMappingConfig{}

	if v, ok := m["external"].(string); ok {
		cfg.ExternalType = v
	}
	if v, ok := m["morphir"].(string); ok {
		cfg.MorphirType = v
	}
	if v, ok := m["bidirectional"].(bool); ok {
		cfg.Bidirectional = v
	}
	cfg.Priority = getIntFromAny(m["priority"], 0)

	return cfg
}

// containerMappingFromMap parses a ContainerMappingConfig from a map.
func containerMappingFromMap(m map[string]any) typemap.ContainerMappingConfig {
	cfg := typemap.ContainerMappingConfig{}

	if v, ok := m["external_pattern"].(string); ok {
		cfg.ExternalPattern = v
	}
	if v, ok := m["morphir_pattern"].(string); ok {
		cfg.MorphirPattern = v
	}
	cfg.TypeParamCount = getIntFromAny(m["type_params"], 0)
	if v, ok := m["bidirectional"].(bool); ok {
		cfg.Bidirectional = v
	}
	cfg.Priority = getIntFromAny(m["priority"], 0)

	return cfg
}

// toolchainsFromMap parses toolchain configurations from a map.
func toolchainsFromMap(m map[string]any, def ToolchainsSection) ToolchainsSection {
	section, ok := m["toolchain"].(map[string]any)
	if !ok {
		return def
	}

	definitions := make(map[string]ToolchainConfig)

	for toolchainName, toolchainValue := range section {
		toolchainMap, ok := toolchainValue.(map[string]any)
		if !ok {
			continue
		}

		tc := toolchainConfigFromMap(toolchainName, toolchainMap)
		definitions[toolchainName] = tc
	}

	if len(definitions) == 0 {
		return def
	}

	return ToolchainsSection{definitions: definitions}
}

// toolchainConfigFromMap parses a ToolchainConfig from a map.
func toolchainConfigFromMap(name string, m map[string]any) ToolchainConfig {
	tc := ToolchainConfig{
		name: name,
	}

	if v, ok := m["version"].(string); ok {
		tc.version = v
	}

	// Parse acquire section
	if acquireMap, ok := m["acquire"].(map[string]any); ok {
		tc.acquire = acquireConfigFromMap(acquireMap)
	}

	// Parse env
	tc.env = getStringMapFromAny(m["env"])

	// Parse working_dir
	if v, ok := m["working_dir"].(string); ok {
		tc.workingDir = v
	}

	// Parse timeout
	if v, ok := m["timeout"].(string); ok {
		tc.timeout = v
	}

	// Parse tasks
	if tasksMap, ok := m["tasks"].(map[string]any); ok {
		tc.tasks = make(map[string]ToolchainTaskConfig)
		for taskName, taskValue := range tasksMap {
			if taskMap, ok := taskValue.(map[string]any); ok {
				tc.tasks[taskName] = toolchainTaskConfigFromMap(taskMap)
			}
		}
	}

	return tc
}

// acquireConfigFromMap parses an AcquireConfig from a map.
func acquireConfigFromMap(m map[string]any) AcquireConfig {
	cfg := AcquireConfig{}

	if v, ok := m["backend"].(string); ok {
		cfg.backend = v
	}
	if v, ok := m["package"].(string); ok {
		cfg.packageVal = v
	}
	if v, ok := m["version"].(string); ok {
		cfg.version = v
	}
	if v, ok := m["executable"].(string); ok {
		cfg.executable = v
	}

	return cfg
}

// toolchainTaskConfigFromMap parses a ToolchainTaskConfig from a map.
func toolchainTaskConfigFromMap(m map[string]any) ToolchainTaskConfig {
	cfg := ToolchainTaskConfig{}

	if v, ok := m["exec"].(string); ok {
		cfg.exec = v
	}

	cfg.args = getStringSliceFromAny(m["args"])

	// Parse inputs
	if inputsMap, ok := m["inputs"].(map[string]any); ok {
		cfg.inputs = inputsConfigFromMap(inputsMap)
	} else if inputsList, ok := m["inputs"].([]any); ok {
		// Support simple array of file patterns
		cfg.inputs = InputsConfig{
			files: getStringSliceFromAny(inputsList),
		}
	}

	// Parse outputs
	if outputsMap, ok := m["outputs"].(map[string]any); ok {
		cfg.outputs = make(map[string]OutputConfig)
		for outputName, outputValue := range outputsMap {
			if outputMap, ok := outputValue.(map[string]any); ok {
				cfg.outputs[outputName] = outputConfigFromMap(outputMap)
			}
		}
	}

	cfg.fulfills = getStringSliceFromAny(m["fulfills"])
	cfg.variants = getStringSliceFromAny(m["variants"])
	cfg.env = getStringMapFromAny(m["env"])

	return cfg
}

// inputsConfigFromMap parses an InputsConfig from a map.
func inputsConfigFromMap(m map[string]any) InputsConfig {
	cfg := InputsConfig{}

	cfg.files = getStringSliceFromAny(m["files"])

	if artifactsMap, ok := m["artifacts"].(map[string]any); ok {
		cfg.artifacts = make(map[string]string)
		for k, v := range artifactsMap {
			if s, ok := v.(string); ok {
				cfg.artifacts[k] = s
			}
		}
	}

	return cfg
}

// outputConfigFromMap parses an OutputConfig from a map.
func outputConfigFromMap(m map[string]any) OutputConfig {
	cfg := OutputConfig{}

	if v, ok := m["path"].(string); ok {
		cfg.path = v
	}
	if v, ok := m["type"].(string); ok {
		cfg.typeVal = v
	}

	return cfg
}
