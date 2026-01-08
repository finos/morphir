package toolchain

import (
	"time"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// Toolchain represents a tool adapter that provides tasks and capabilities.
type Toolchain struct {
	// Name is the unique identifier for this toolchain (e.g., "morphir-elm", "wit")
	Name string

	// Version is the toolchain version (optional)
	Version string

	// Description is a human-readable description of this toolchain
	Description string

	// Acquire specifies how to acquire/invoke this toolchain
	Acquire AcquireConfig

	// Env contains environment variables for task execution
	Env map[string]string

	// WorkingDir is the working directory for task execution (relative to project root)
	WorkingDir string

	// Timeout is the default timeout for task execution
	Timeout time.Duration

	// Tasks are the task definitions provided by this toolchain
	Tasks []TaskDef

	// Type indicates whether this is a native or external toolchain
	Type ToolchainType
}

// ToolchainType indicates whether a toolchain is native (in-process) or external (process-based).
type ToolchainType string

const (
	// ToolchainTypeNative indicates an in-process Go implementation
	ToolchainTypeNative ToolchainType = "native"

	// ToolchainTypeExternal indicates a process-based external tool
	ToolchainTypeExternal ToolchainType = "external"
)

// AcquireConfig specifies how to acquire and invoke a toolchain.
type AcquireConfig struct {
	// Backend specifies the acquisition method ("path", "npx", "npm", "mise", etc.)
	Backend string

	// Package is the package name for npm/npx/mise backends
	Package string

	// Version is the version constraint for package-based backends
	Version string

	// Executable is the executable name for path-based backend
	Executable string
}

// TaskDef defines a concrete task implementation provided by a toolchain.
type TaskDef struct {
	// Name is the task identifier within this toolchain
	Name string

	// Description is a human-readable description
	Description string

	// Exec is the executable to invoke (for external toolchains)
	Exec string

	// Args are the command-line arguments (supports variable substitution)
	Args []string

	// Inputs are input file patterns or artifact references
	Inputs InputSpec

	// Outputs are the outputs produced by this task
	Outputs map[string]OutputSpec

	// Fulfills lists the target names this task fulfills
	Fulfills []string

	// Variants are the supported variants for this task (e.g., ["scala", "typescript"])
	Variants []string

	// Env contains task-specific environment variables
	Env map[string]string

	// WorkingDir is the task-specific working directory (overrides toolchain default)
	WorkingDir string

	// Timeout is the task-specific timeout (overrides toolchain default)
	Timeout time.Duration
}

// InputSpec specifies task inputs (files or artifact references).
type InputSpec struct {
	// Files are file glob patterns for file inputs
	Files []string

	// Artifacts are references to other task outputs (@toolchain/task:artifact)
	Artifacts map[string]string
}

// OutputSpec specifies a task output.
type OutputSpec struct {
	// Path is the output file path (relative to task output directory)
	Path string

	// Type is the artifact type (e.g., "morphir-ir", "generated-code")
	Type string
}

// Target represents a CLI-facing capability that tasks can fulfill.
type Target struct {
	// Name is the target identifier (e.g., "make", "gen", "validate")
	Name string

	// Description is a human-readable description
	Description string

	// Produces are the artifact types this target produces
	Produces []string

	// Requires are the artifact types this target requires
	Requires []string

	// Variants are the supported variants (e.g., ["scala", "typescript"])
	Variants []string
}

// Workflow defines a named orchestration of targets.
type Workflow struct {
	// Name is the workflow identifier (e.g., "build", "ci", "release")
	Name string

	// Description is a human-readable description
	Description string

	// Extends is the name of the workflow this extends (optional)
	Extends string

	// Stages are the execution stages
	Stages []WorkflowStage
}

// WorkflowStage represents a stage in a workflow.
type WorkflowStage struct {
	// Name is the stage identifier
	Name string

	// Targets are the target names to execute in this stage
	Targets []string

	// Parallel indicates whether targets can run in parallel
	Parallel bool

	// Condition is an optional condition for conditional execution
	Condition string
}

// TaskMetadata captures metadata about a task execution.
type TaskMetadata struct {
	// ToolchainName is the name of the toolchain that executed this task
	ToolchainName string

	// TaskName is the name of the task
	TaskName string

	// InputsHash is a hash of the task inputs (for caching)
	InputsHash string

	// StartTime is when the task started
	StartTime time.Time

	// EndTime is when the task finished
	EndTime time.Time

	// Duration is the task execution duration
	Duration time.Duration

	// ExitCode is the process exit code (for external toolchains)
	ExitCode int

	// Success indicates whether the task succeeded
	Success bool
}

// TaskResult captures the result of a task execution.
type TaskResult struct {
	// Metadata is the task execution metadata
	Metadata TaskMetadata

	// Outputs are the actual output values produced by the task
	Outputs map[string]any

	// Diagnostics are the diagnostics produced by the task
	Diagnostics []pipeline.Diagnostic

	// Artifacts are the artifacts produced by the task
	Artifacts []pipeline.Artifact

	// Error is the error if the task failed
	Error error
}

// Registry manages registered toolchains and targets.
type Registry struct {
	toolchains map[string]Toolchain
	targets    map[string]Target
}

// NewRegistry creates a new empty registry.
func NewRegistry() *Registry {
	return &Registry{
		toolchains: make(map[string]Toolchain),
		targets:    make(map[string]Target),
	}
}

// Register registers a toolchain in the registry.
func (r *Registry) Register(tc Toolchain) {
	r.toolchains[tc.Name] = tc
}

// RegisterTarget registers a target in the registry.
func (r *Registry) RegisterTarget(t Target) {
	r.targets[t.Name] = t
}

// GetToolchain retrieves a toolchain by name.
func (r *Registry) GetToolchain(name string) (Toolchain, bool) {
	tc, ok := r.toolchains[name]
	return tc, ok
}

// GetTarget retrieves a target by name.
func (r *Registry) GetTarget(name string) (Target, bool) {
	t, ok := r.targets[name]
	return t, ok
}

// ListToolchains returns all registered toolchain names.
func (r *Registry) ListToolchains() []string {
	names := make([]string, 0, len(r.toolchains))
	for name := range r.toolchains {
		names = append(names, name)
	}
	return names
}

// ListTargets returns all registered target names.
func (r *Registry) ListTargets() []string {
	names := make([]string, 0, len(r.targets))
	for name := range r.targets {
		names = append(names, name)
	}
	return names
}

// OutputDirStructure manages the output directory structure.
type OutputDirStructure struct {
	// Root is the root output directory (.morphir/out)
	Root vfs.VPath

	// VFS is the virtual file system
	VFS vfs.VFS
}

// NewOutputDirStructure creates a new output directory structure manager.
func NewOutputDirStructure(root vfs.VPath, vfsInstance vfs.VFS) *OutputDirStructure {
	return &OutputDirStructure{
		Root: root,
		VFS:  vfsInstance,
	}
}

// TaskOutputDir returns the output directory path for a task.
func (o *OutputDirStructure) TaskOutputDir(toolchainName, taskName string) (vfs.VPath, error) {
	return o.Root.Join(toolchainName, taskName)
}

// MetaPath returns the path to the meta.json file for a task.
func (o *OutputDirStructure) MetaPath(toolchainName, taskName string) (vfs.VPath, error) {
	taskDir, err := o.TaskOutputDir(toolchainName, taskName)
	if err != nil {
		return vfs.VPath{}, err
	}
	return taskDir.Join("meta.json")
}

// DiagnosticsPath returns the path to the diagnostics.jsonl file for a task.
func (o *OutputDirStructure) DiagnosticsPath(toolchainName, taskName string) (vfs.VPath, error) {
	taskDir, err := o.TaskOutputDir(toolchainName, taskName)
	if err != nil {
		return vfs.VPath{}, err
	}
	return taskDir.Join("diagnostics.jsonl")
}

// OutputPath returns the path to a specific output artifact for a task.
func (o *OutputDirStructure) OutputPath(toolchainName, taskName, outputName string) (vfs.VPath, error) {
	taskDir, err := o.TaskOutputDir(toolchainName, taskName)
	if err != nil {
		return vfs.VPath{}, err
	}
	return taskDir.Join(outputName)
}
