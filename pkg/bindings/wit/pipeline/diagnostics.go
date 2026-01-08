package pipeline

import (
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// Diagnostic codes for WIT pipeline operations.
// These codes categorize specific issues that can occur during WIT↔IR conversion.
const (
	// CodeIntPrecisionLost indicates integer size or signedness information was lost.
	// Emitted when converting u8/u16/u64, s8/s16/s32/s64 to Morphir Int.
	CodeIntPrecisionLost = "WIT001"

	// CodeFloatPrecisionLost indicates float precision hint was lost.
	// Emitted when converting f32 to Morphir Float (f64 is lossless).
	CodeFloatPrecisionLost = "WIT002"

	// CodeFlagsUnsupported indicates flags type is not supported.
	// WIT flags have no direct Morphir IR equivalent.
	CodeFlagsUnsupported = "WIT003"

	// CodeResourceUnsupported indicates resource type is not supported.
	// WIT resources have handle semantics that don't map to Morphir.
	CodeResourceUnsupported = "WIT004"

	// CodeRoundTripMismatch indicates round-trip produced different output.
	// Emitted when WIT→IR→WIT does not produce semantically equivalent WIT.
	CodeRoundTripMismatch = "WIT005"

	// CodeUnknownType indicates an unknown type was encountered.
	CodeUnknownType = "WIT006"

	// CodeParseError indicates a WIT parsing error.
	CodeParseError = "WIT007"

	// CodeConversionError indicates a general conversion error.
	CodeConversionError = "WIT008"
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

// IntPrecisionLost creates a diagnostic for integer precision loss.
func IntPrecisionLost(witType, stepName string) pipeline.Diagnostic {
	return DiagnosticWarn(
		CodeIntPrecisionLost,
		"integer size/signedness lost: "+witType+" → Int",
		stepName,
	)
}

// FloatPrecisionLost creates a diagnostic for float precision loss.
func FloatPrecisionLost(witType, stepName string) pipeline.Diagnostic {
	return DiagnosticWarn(
		CodeFloatPrecisionLost,
		"float precision hint lost: "+witType+" → Float",
		stepName,
	)
}

// FlagsUnsupported creates a diagnostic for unsupported flags type.
func FlagsUnsupported(name, stepName string, strict bool) pipeline.Diagnostic {
	severity := pipeline.SeverityWarn
	if strict {
		severity = pipeline.SeverityError
	}
	return pipeline.Diagnostic{
		Severity: severity,
		Code:     CodeFlagsUnsupported,
		Message:  "flags type not supported: " + name,
		StepName: stepName,
	}
}

// ResourceUnsupported creates a diagnostic for unsupported resource type.
func ResourceUnsupported(name, stepName string, strict bool) pipeline.Diagnostic {
	severity := pipeline.SeverityWarn
	if strict {
		severity = pipeline.SeverityError
	}
	return pipeline.Diagnostic{
		Severity: severity,
		Code:     CodeResourceUnsupported,
		Message:  "resource type not supported: " + name,
		StepName: stepName,
	}
}

// RoundTripMismatch creates a diagnostic for round-trip mismatch.
func RoundTripMismatch(stepName string) pipeline.Diagnostic {
	return DiagnosticWarn(
		CodeRoundTripMismatch,
		"round-trip WIT→IR→WIT produced semantically different output",
		stepName,
	)
}

// UnknownType creates a diagnostic for an unknown type.
func UnknownType(typeName, stepName string) pipeline.Diagnostic {
	return DiagnosticError(
		CodeUnknownType,
		"unknown type: "+typeName,
		stepName,
	)
}

// ParseError creates a diagnostic for a parse error.
func ParseError(message, stepName string) pipeline.Diagnostic {
	return DiagnosticError(
		CodeParseError,
		"parse error: "+message,
		stepName,
	)
}

// ConversionError creates a diagnostic for a conversion error.
func ConversionError(message, stepName string) pipeline.Diagnostic {
	return DiagnosticError(
		CodeConversionError,
		"conversion error: "+message,
		stepName,
	)
}

// HasWarnings checks if any diagnostics are warnings.
func HasWarnings(diagnostics []pipeline.Diagnostic) bool {
	for _, d := range diagnostics {
		if d.Severity == pipeline.SeverityWarn {
			return true
		}
	}
	return false
}

// HasErrors checks if any diagnostics are errors.
func HasErrors(diagnostics []pipeline.Diagnostic) bool {
	for _, d := range diagnostics {
		if d.Severity == pipeline.SeverityError {
			return true
		}
	}
	return false
}

// FilterBySeverity returns diagnostics matching the given severity.
func FilterBySeverity(diagnostics []pipeline.Diagnostic, severity pipeline.Severity) []pipeline.Diagnostic {
	var result []pipeline.Diagnostic
	for _, d := range diagnostics {
		if d.Severity == severity {
			result = append(result, d)
		}
	}
	return result
}
