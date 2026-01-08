package pipeline

import (
	"encoding/json"
	"fmt"

	"github.com/finos/morphir/pkg/vfs"
)

// ValidateInput provides the input for the validation step.
type ValidateInput struct {
	// IRPath is the path to the Morphir IR file to validate.
	IRPath vfs.VPath
	// Version specifies which schema version to validate against.
	// If 0, the version is auto-detected from the formatVersion field.
	Version int
}

// ValidateOutput contains the result of the validation step.
type ValidateOutput struct {
	Valid   bool
	Version int
	Path    string
	Errors  []string
	RawData any
}

// NewValidateStep creates a pipeline step that validates Morphir IR.
// The step reads the IR file from VFS, validates it against the JSON schema,
// and emits diagnostics for any validation errors.
func NewValidateStep() Step[ValidateInput, ValidateOutput] {
	return NewStep[ValidateInput, ValidateOutput](
		"validate",
		"Validates Morphir IR against JSON schema",
		func(ctx Context, in ValidateInput) (ValidateOutput, StepResult) {
			var result StepResult
			var output ValidateOutput

			// Resolve the IR file from VFS
			entry, _, err := ctx.VFS.Resolve(in.IRPath)
			if err != nil {
				result.Err = fmt.Errorf("failed to resolve IR path %s: %w", in.IRPath, err)
				result.Diagnostics = []Diagnostic{{
					Severity: SeverityError,
					Code:     "VALIDATE_RESOLVE_ERROR",
					Message:  result.Err.Error(),
					StepName: "validate",
				}}
				return output, result
			}

			// Ensure it's a file
			file, ok := entry.(vfs.File)
			if !ok {
				result.Err = fmt.Errorf("path %s is not a file", in.IRPath)
				result.Diagnostics = []Diagnostic{{
					Severity: SeverityError,
					Code:     "VALIDATE_NOT_FILE",
					Message:  result.Err.Error(),
					StepName: "validate",
				}}
				return output, result
			}

			// Read file contents
			data, err := file.Bytes()
			if err != nil {
				result.Err = fmt.Errorf("failed to read IR file: %w", err)
				result.Diagnostics = []Diagnostic{{
					Severity: SeverityError,
					Code:     "VALIDATE_READ_ERROR",
					Message:  result.Err.Error(),
					StepName: "validate",
				}}
				return output, result
			}

			// Validate the IR using the internal validation logic
			valResult, err := validateIRBytes(data, in.IRPath.String(), in.Version)
			if err != nil {
				result.Err = err
				result.Diagnostics = []Diagnostic{{
					Severity: SeverityError,
					Code:     "VALIDATE_INTERNAL_ERROR",
					Message:  err.Error(),
					StepName: "validate",
				}}
				return output, result
			}

			output = ValidateOutput{
				Valid:   valResult.Valid,
				Version: valResult.Version,
				Path:    valResult.Path,
				Errors:  valResult.Errors,
				RawData: valResult.RawData,
			}

			// Convert validation errors to diagnostics
			if !valResult.Valid {
				for _, errMsg := range valResult.Errors {
					result.Diagnostics = append(result.Diagnostics, Diagnostic{
						Severity: SeverityError,
						Code:     "VALIDATE_SCHEMA_ERROR",
						Message:  errMsg,
						Location: &Location{Path: in.IRPath},
						StepName: "validate",
					})
				}
			}

			// Generate report artifact
			reportData, _ := json.MarshalIndent(map[string]any{
				"valid":   output.Valid,
				"version": output.Version,
				"path":    output.Path,
				"errors":  output.Errors,
			}, "", "  ")

			result.Artifacts = []Artifact{{
				Kind:        ArtifactReport,
				Path:        vfs.MustVPath("/.morphir/validation-report.json"),
				ContentType: "application/json",
				Content:     reportData,
			}}

			return output, result
		},
	)
}

// InternalValidationResult mirrors the validation.Result for internal use
// to avoid circular dependencies. It is exported to allow injection of
// custom validation functions from cmd/morphir.
type InternalValidationResult struct {
	Valid   bool
	Version int
	Path    string
	Errors  []string
	RawData any
}

// Alias for internal use (backwards compatibility)
type internalValidationResult = InternalValidationResult

// validateIRBytes is a placeholder that will call the actual validation logic.
// This is implemented separately to allow for dependency injection in tests
// and to break circular dependencies with pkg/tooling/validation.
var validateIRBytes = defaultValidateIRBytes

// defaultValidateIRBytes provides basic IR validation.
// The actual implementation calls pkg/tooling/validation.ValidateBytes.
func defaultValidateIRBytes(data []byte, sourcePath string, version int) (*internalValidationResult, error) {
	// Detect version from IR if not specified
	detectedVersion := version
	if detectedVersion == 0 {
		var partial struct {
			FormatVersion int `json:"formatVersion"`
		}
		if err := json.Unmarshal(data, &partial); err != nil {
			return &internalValidationResult{
				Valid:  false,
				Path:   sourcePath,
				Errors: []string{fmt.Sprintf("failed to parse JSON: %v", err)},
			}, nil
		}
		detectedVersion = partial.FormatVersion
		if detectedVersion < 1 || detectedVersion > 3 {
			return &internalValidationResult{
				Valid:   false,
				Version: detectedVersion,
				Path:    sourcePath,
				Errors:  []string{fmt.Sprintf("invalid formatVersion: %d (expected 1, 2, or 3)", detectedVersion)},
			}, nil
		}
	}

	// Parse the IR JSON
	var irData any
	if err := json.Unmarshal(data, &irData); err != nil {
		return &internalValidationResult{
			Valid:   false,
			Version: detectedVersion,
			Path:    sourcePath,
			Errors:  []string{fmt.Sprintf("invalid JSON: %v", err)},
		}, nil
	}

	// For now, return valid if JSON parses successfully
	// The full schema validation is handled by cmd/morphir which has access to
	// pkg/tooling/validation. This step provides the pipeline interface.
	return &internalValidationResult{
		Valid:   true,
		Version: detectedVersion,
		Path:    sourcePath,
		RawData: irData,
	}, nil
}

// SetValidateIRBytes allows setting a custom validation function.
// This is useful for testing or for injecting the full validation logic
// from pkg/tooling/validation.
func SetValidateIRBytes(fn func(data []byte, sourcePath string, version int) (*internalValidationResult, error)) {
	validateIRBytes = fn
}
