package decorations

import (
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir/pkg/models/ir"
	jsoncodec "github.com/finos/morphir/pkg/models/ir/codec/json"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

// ValidationError represents an error encountered during decoration value validation.
type ValidationError struct {
	NodePath ir.NodePath
	Message  string
	Cause    error
}

func (e ValidationError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("decoration validation error at %q: %s: %v", e.NodePath.String(), e.Message, e.Cause)
	}
	return fmt.Sprintf("decoration validation error at %q: %s", e.NodePath.String(), e.Message)
}

func (e ValidationError) Unwrap() error {
	return e.Cause
}

// ValidationResult contains the result of validating decoration values.
type ValidationResult struct {
	Valid   bool
	Errors  []ValidationError
	Checked int // Number of values checked
}

// ValidateDecorationValue validates a single decoration value against its schema.
//
// This function:
//   - Decodes the value JSON into a Morphir IR Value
//   - Validates the value structure is valid Morphir IR
//   - Optionally validates the value conforms to the expected type (if type checking is implemented)
//
// For now, this performs structural validation. Full type checking would require
// implementing a type checker, which is a larger feature.
func ValidateDecorationValue(
	decIR decorationmodels.DecorationIR,
	entryPoint string,
	nodePath ir.NodePath,
	valueJSON json.RawMessage,
) error {
	// Decode the value to ensure it's valid Morphir IR JSON
	opts := jsoncodec.Options{
		FormatVersion: jsoncodec.FormatV3,
	}

	decodeUnitAttr := func(raw json.RawMessage) (ir.Unit, error) {
		return ir.Unit{}, nil
	}

	decodeValueUnitAttr := func(raw json.RawMessage) (ir.Unit, error) {
		return ir.Unit{}, nil
	}

	value, err := jsoncodec.DecodeValue(opts, decodeUnitAttr, decodeValueUnitAttr, valueJSON)
	if err != nil {
		return ValidationError{
			NodePath: nodePath,
			Message:  "invalid Morphir IR value JSON",
			Cause:    err,
		}
	}

	// Perform type checking
	typeChecker, err := NewTypeChecker(decIR, entryPoint)
	if err != nil {
		return ValidationError{
			NodePath: nodePath,
			Message:  "failed to create type checker",
			Cause:    err,
		}
	}

	if err := typeChecker.CheckValueType(value); err != nil {
		return ValidationError{
			NodePath: nodePath,
			Message:  "type check failed",
			Cause:    err,
		}
	}

	return nil
}

// ValidateDecorationValues validates all decoration values in a DecorationValues collection
// against their decoration schema.
//
// This validates each value:
//   - Can be decoded as valid Morphir IR
//   - Conforms to the type defined at the entry point
//
// Returns a ValidationResult with all validation errors found.
func ValidateDecorationValues(
	decIR decorationmodels.DecorationIR,
	entryPoint string,
	values decorationmodels.DecorationValues,
) ValidationResult {
	result := ValidationResult{
		Valid:   true,
		Errors:  []ValidationError{},
		Checked: 0,
	}

	allValues := values.All()
	result.Checked = len(allValues)

	for nodePathStr, valueJSON := range allValues {
		// Parse the NodePath string
		nodePath, err := ir.ParseNodePath(nodePathStr)
		if err != nil {
			result.Valid = false
			result.Errors = append(result.Errors, ValidationError{
				NodePath: ir.NodePath{}, // Can't construct valid path
				Message:  fmt.Sprintf("invalid NodePath %q", nodePathStr),
				Cause:    err,
			})
			continue
		}

		// Validate the value
		if err := ValidateDecorationValue(decIR, entryPoint, nodePath, valueJSON); err != nil {
			result.Valid = false
			var valErr ValidationError
			if v, ok := err.(ValidationError); ok {
				valErr = v
			} else {
				valErr = ValidationError{
					NodePath: nodePath,
					Message:  "validation failed",
					Cause:    err,
				}
			}
			result.Errors = append(result.Errors, valErr)
		}
	}

	return result
}

// ValidateDecorationValueFile validates all decoration values in a file against their schema.
//
// This is a convenience function that loads the file and validates all values.
func ValidateDecorationValueFile(
	decIR decorationmodels.DecorationIR,
	entryPoint string,
	filePath string,
) (ValidationResult, error) {
	values, err := LoadDecorationValues(filePath)
	if err != nil {
		return ValidationResult{
			Valid: false,
			Errors: []ValidationError{{
				NodePath: ir.NodePath{},
				Message:  "failed to load decoration values file",
				Cause:    err,
			}},
		}, err
	}

	result := ValidateDecorationValues(decIR, entryPoint, values)
	return result, nil
}
