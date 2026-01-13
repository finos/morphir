package pipeline

import (
	"time"

	"github.com/finos/morphir/pkg/vfs"
	"github.com/rs/zerolog"
)

// Mode represents the execution mode for pipeline operations.
type Mode string

const (
	ModeDefault     Mode = "default"     // Default mode with standard output
	ModeInteractive Mode = "interactive" // Interactive mode with rich TUI
	ModeJSON        Mode = "json"        // JSON output mode for programmatic use
)

// Context is immutable execution context passed to all pipeline steps.
type Context struct {
	WorkspaceRoot string
	FormatVersion int
	Now           time.Time
	Mode          Mode
	VFS           vfs.VFS
	Logger        zerolog.Logger
}

// NewContext constructs a new pipeline context.
// Logger defaults to a disabled (nop) logger if not provided via WithLogger.
func NewContext(workspaceRoot string, formatVersion int, mode Mode, vfsInstance vfs.VFS) Context {
	return Context{
		WorkspaceRoot: workspaceRoot,
		FormatVersion: formatVersion,
		Now:           time.Now(),
		Mode:          mode,
		VFS:           vfsInstance,
		Logger:        zerolog.Nop(),
	}
}

// WithLogger returns a new Context with the specified logger.
// The original context is not modified.
func (c Context) WithLogger(logger zerolog.Logger) Context {
	c.Logger = logger
	return c
}

// Severity indicates the importance level of a diagnostic.
type Severity string

const (
	SeverityInfo  Severity = "info"
	SeverityWarn  Severity = "warn"
	SeverityError Severity = "error"
)

// Location identifies a position in a source file.
type Location struct {
	Path   vfs.VPath
	Line   int
	Column int
}

// Diagnostic represents a message about code quality, errors, or warnings.
type Diagnostic struct {
	Severity Severity
	Code     string
	Message  string
	Location *Location
	StepName string
}

// ArtifactKind classifies the type of artifact produced.
type ArtifactKind string

const (
	ArtifactIR       ArtifactKind = "ir"
	ArtifactReport   ArtifactKind = "report"
	ArtifactCodegen  ArtifactKind = "codegen"
	ArtifactMetadata ArtifactKind = "metadata"
)

// Artifact represents a generated output from a pipeline step.
type Artifact struct {
	Kind        ArtifactKind
	Path        vfs.VPath
	ContentType string
	Content     []byte
}

// StepResult captures the output of a single pipeline step.
type StepResult struct {
	Diagnostics []Diagnostic
	Artifacts   []Artifact
	Err         error
}

// StepExecution records metadata about a step's execution.
type StepExecution struct {
	Name        string
	Description string
	Started     time.Time
	Finished    time.Time
	Duration    time.Duration
	Result      StepResult
}

// PipelineResult aggregates execution metadata across all steps.
type PipelineResult struct {
	Diagnostics []Diagnostic
	Artifacts   []Artifact
	Steps       []StepExecution
}
