package pipeline

import (
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// Diagnostic codes for Go pipeline operations.
// These codes categorize specific issues that can occur during IR→Go conversion.
const (
	// CodeTypeMappingLost indicates type mapping information was lost.
	// Emitted when IR type semantics cannot be fully preserved in Go.
	CodeTypeMappingLost = "GO001"

	// CodeUnsupportedConstruct indicates an unsupported IR construct.
	// Emitted when encountering IR features without Go equivalents.
	CodeUnsupportedConstruct = "GO002"

	// CodeNameCollision indicates a name collision in generated code.
	// Emitted when multiple IR names map to the same Go identifier.
	CodeNameCollision = "GO003"

	// CodeInvalidIdentifier indicates an invalid Go identifier was generated.
	// Emitted when IR names cannot be converted to valid Go identifiers.
	CodeInvalidIdentifier = "GO004"

	// CodeModuleStructureConflict indicates a module structure conflict.
	// Emitted when IR package structure conflicts with Go module conventions.
	CodeModuleStructureConflict = "GO005"

	// CodeParseError indicates an IR parsing error.
	CodeParseError = "GO006"

	// CodeGenerationError indicates a general code generation error.
	CodeGenerationError = "GO007"

	// CodeFormatError indicates a code formatting error.
	// Emitted when gofmt or goimports fails on generated code.
	CodeFormatError = "GO008"
)

// DiagnosticInfo creates an informational diagnostic.
func DiagnosticInfo(code, message, stepName string) pipeline.Diagnostic {
	return pipeline.Diagnostic{
		Severity: pipeline.SeverityInfo,
		Code:     code,
		Message:  message,
		StepName: stepName,
	}
}

// DiagnosticWarn creates a warning diagnostic.
func DiagnosticWarn(code, message, stepName string) pipeline.Diagnostic {
	return pipeline.Diagnostic{
		Severity: pipeline.SeverityWarn,
		Code:     code,
		Message:  message,
		StepName: stepName,
	}
}

// DiagnosticError creates an error diagnostic.
func DiagnosticError(code, message, stepName string) pipeline.Diagnostic {
	return pipeline.Diagnostic{
		Severity: pipeline.SeverityError,
		Code:     code,
		Message:  message,
		StepName: stepName,
	}
}

// DiagnosticWithLocation adds location information to a diagnostic.
func DiagnosticWithLocation(d pipeline.Diagnostic, path vfs.VPath, line, column int) pipeline.Diagnostic {
	d.Location = &pipeline.Location{
		Path:   path,
		Line:   line,
		Column: column,
	}
	return d
}
