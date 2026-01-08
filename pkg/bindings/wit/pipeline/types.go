package pipeline

import (
	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/models/ir"
	"github.com/finos/morphir/pkg/vfs"
)

// SourceLocation represents a position in a WIT source file.
// It implements the attribute type parameter for Morphir IR types.
type SourceLocation struct {
	File   string
	Line   int
	Column int
}

// MakeInput is input for the WIT make step (frontend compilation).
// It accepts either inline WIT source code or a file path to read from VFS.
type MakeInput struct {
	// Source provides WIT source code directly.
	// If non-empty, this takes precedence over FilePath.
	Source string

	// FilePath is the path to a .wit file to read from VFS.
	// Used only if Source is empty.
	FilePath vfs.VPath

	// Options controls compilation behavior.
	Options MakeOptions
}

// MakeOptions configures the WIT make step.
type MakeOptions struct {
	// WarningsAsErrors treats warnings as errors.
	// When true, any lossy type mapping will cause compilation to fail.
	WarningsAsErrors bool

	// StrictMode fails on unsupported constructs.
	// When true, unsupported WIT features (flags, resource) produce errors
	// instead of warnings.
	StrictMode bool
}

// MakeOutput is output from the WIT make step.
type MakeOutput struct {
	// Module is the compiled Morphir IR module.
	// The type parameters are SourceLocation for both type and value attributes.
	Module ir.ModuleDefinition[SourceLocation, SourceLocation]

	// SourcePackage preserves the original WIT package for reference.
	// This is useful for round-trip validation and debugging.
	SourcePackage domain.Package
}

// GenInput is input for the WIT gen step (backend generation).
type GenInput struct {
	// Module is the Morphir IR module to generate WIT from.
	// Accepts any attribute types since we only use the structure.
	Module ir.ModuleDefinition[any, any]

	// OutputPath is optional path for generated .wit file.
	// If specified, the generated WIT will be written as an artifact.
	OutputPath vfs.VPath

	// Options controls generation behavior.
	Options GenOptions
}

// GenOptions configures the WIT gen step.
type GenOptions struct {
	// WarningsAsErrors treats warnings as errors.
	// When true, any issues during IR→WIT conversion will cause generation to fail.
	WarningsAsErrors bool

	// Format controls output formatting options.
	Format FormatOptions
}

// FormatOptions controls WIT output formatting.
type FormatOptions struct {
	// IndentSize is the number of spaces for indentation.
	// Default is 4.
	IndentSize int

	// IncludeComments preserves documentation comments in output.
	// Default is true.
	IncludeComments bool
}

// DefaultFormatOptions returns sensible default formatting options.
func DefaultFormatOptions() FormatOptions {
	return FormatOptions{
		IndentSize:      4,
		IncludeComments: true,
	}
}

// GenOutput is output from the WIT gen step.
type GenOutput struct {
	// Package is the generated WIT domain package.
	Package domain.Package

	// Source is the generated WIT source code.
	Source string
}

// BuildInput is input for the full build pipeline (WIT → IR → WIT).
type BuildInput struct {
	// Source provides WIT source code directly.
	// If non-empty, this takes precedence over FilePath.
	Source string

	// FilePath is the path to a .wit file to read from VFS.
	// Used only if Source is empty.
	FilePath vfs.VPath

	// OutputPath is the path to write the generated .wit file.
	// If empty, no file artifact is produced.
	OutputPath vfs.VPath

	// MakeOptions controls the make (WIT → IR) step.
	MakeOptions MakeOptions

	// GenOptions controls the gen (IR → WIT) step.
	GenOptions GenOptions
}

// BuildOutput is output from the full build pipeline.
type BuildOutput struct {
	// Make contains output from the make step.
	Make MakeOutput

	// Gen contains output from the gen step.
	Gen GenOutput

	// RoundTripValid indicates if WIT→IR→WIT produces semantically equivalent output.
	// This is determined by comparing the source and generated packages.
	RoundTripValid bool
}
