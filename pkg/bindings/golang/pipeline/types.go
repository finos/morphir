package pipeline

import (
	"github.com/finos/morphir/pkg/models/ir"
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// SourceLocation represents a position in a Go source file.
// It implements the attribute type parameter for Morphir IR types.
type SourceLocation struct {
	File   string
	Line   int
	Column int
}

// MakeInput is input for the Go make step (frontend compilation).
// This is a placeholder for future Go → Morphir IR functionality.
type MakeInput struct {
	// Source provides Go source code directly.
	// If non-empty, this takes precedence over FilePath.
	Source string

	// FilePath is the path to a .go file to read from VFS.
	// Used only if Source is empty.
	FilePath vfs.VPath

	// Options controls compilation behavior.
	Options MakeOptions
}

// MakeOptions configures the Go make step.
type MakeOptions struct {
	// WarningsAsErrors treats warnings as errors.
	WarningsAsErrors bool

	// StrictMode fails on unsupported constructs.
	StrictMode bool
}

// MakeOutput is output from the Go make step.
type MakeOutput struct {
	// Module is the compiled Morphir IR module.
	Module ir.ModuleDefinition[SourceLocation, SourceLocation]
}

// GenInput is input for the Go gen step (backend generation).
type GenInput struct {
	// Module is the Morphir IR module to generate Go code from.
	// Accepts any attribute types since we only use the structure.
	Module ir.ModuleDefinition[any, any]

	// OutputDir is the directory where generated Go files will be written.
	OutputDir vfs.VPath

	// Options controls generation behavior.
	Options GenOptions
}

// GenOptions configures the Go gen step.
type GenOptions struct {
	// ModulePath is the Go module path (e.g., "github.com/example/myapp").
	// This is used in the generated go.mod file.
	ModulePath string

	// Workspace enables multi-module workspace output.
	// When true, generates go.work and separate go.mod per package.
	// When false, generates a single go.mod at OutputDir root.
	Workspace bool

	// WarningsAsErrors treats warnings as errors.
	WarningsAsErrors bool

	// Format controls output formatting options.
	Format FormatOptions
}

// FormatOptions controls Go code output formatting.
type FormatOptions struct {
	// UseGofmt runs gofmt on generated code.
	// Default is true.
	UseGofmt bool

	// UseGoimports runs goimports on generated code.
	// Default is false.
	UseGoimports bool

	// TabWidth is the number of spaces for indentation.
	// Default is 0 (use tabs).
	TabWidth int
}

// DefaultFormatOptions returns sensible default formatting options.
func DefaultFormatOptions() FormatOptions {
	return FormatOptions{
		UseGofmt:     true,
		UseGoimports: false,
		TabWidth:     0, // Use tabs (Go convention)
	}
}

// GenOutput is output from the Go gen step.
type GenOutput struct {
	// GeneratedFiles is a map of file paths to generated content.
	// Keys are relative paths from OutputDir.
	GeneratedFiles map[string]string

	// ModuleFiles lists artifacts for generated go.mod files.
	ModuleFiles []pipeline.Artifact

	// WorkspaceFile is the artifact for generated go.work file (if any).
	WorkspaceFile *pipeline.Artifact
}

// BuildInput is input for the Go build step (full pipeline).
type BuildInput struct {
	// IRPath is the path to a Morphir IR JSON file.
	IRPath vfs.VPath

	// OutputDir is the directory where generated Go files will be written.
	OutputDir vfs.VPath

	// Options controls build behavior.
	Options BuildOptions
}

// BuildOptions configures the Go build step.
type BuildOptions struct {
	// MakeOptions controls the make step (if used).
	MakeOptions MakeOptions

	// GenOptions controls the gen step.
	GenOptions GenOptions
}

// BuildOutput is output from the Go build step.
type BuildOutput struct {
	// GenOutput contains the generation results.
	GenOutput GenOutput
}
