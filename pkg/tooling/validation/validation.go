// Package validation provides Morphir IR validation using JSON Schema.
package validation

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/finos/morphir-go/pkg/models/ir/schema"
	"github.com/santhosh-tekuri/jsonschema/v6"
	"sigs.k8s.io/yaml"
)

// Result contains the validation outcome.
type Result struct {
	Valid   bool     `json:"valid"`
	Version int      `json:"version"`
	Errors  []string `json:"errors,omitempty"`
	Path    string   `json:"path"`
	// RawData contains the parsed IR data for context extraction in reports.
	// This is not serialized to JSON output.
	RawData any `json:"-"`
}

// Options configures the validation behavior.
type Options struct {
	// Version specifies which schema version to validate against.
	// If 0, the version is auto-detected from the formatVersion field.
	Version int
}

// DefaultOptions returns the default validation options.
func DefaultOptions() Options {
	return Options{
		Version: 0, // Auto-detect
	}
}

// ValidateFile validates a Morphir IR file against the JSON schema.
func ValidateFile(path string, opts Options) (*Result, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	return ValidateBytes(data, path, opts)
}

// ValidateBytes validates Morphir IR JSON data against the schema.
func ValidateBytes(data []byte, sourcePath string, opts Options) (*Result, error) {
	// Parse the IR to determine format version if not specified
	version := opts.Version
	if version == 0 {
		detectedVersion, err := detectVersion(data)
		if err != nil {
			return &Result{
				Valid:  false,
				Path:   sourcePath,
				Errors: []string{fmt.Sprintf("failed to detect format version: %v", err)},
			}, nil
		}
		version = detectedVersion
	}

	// Get the schema for the detected version
	schemaVersion := schema.Version(version)
	schemaData, err := schema.GetSchema(schemaVersion)
	if err != nil {
		return nil, fmt.Errorf("failed to get schema for version %d: %w", version, err)
	}

	// Convert YAML schema to JSON for the validator
	schemaJSON, err := yaml.YAMLToJSON(schemaData)
	if err != nil {
		return nil, fmt.Errorf("failed to convert schema to JSON: %w", err)
	}

	// Parse the schema JSON into a document
	var schemaDoc any
	if err := json.Unmarshal(schemaJSON, &schemaDoc); err != nil {
		return nil, fmt.Errorf("failed to parse schema JSON: %w", err)
	}

	// Compile the schema
	compiler := jsonschema.NewCompiler()
	schemaURI := fmt.Sprintf("https://morphir.finos.org/schemas/morphir-ir-v%d.json", version)
	if err := compiler.AddResource(schemaURI, schemaDoc); err != nil {
		return nil, fmt.Errorf("failed to add schema resource: %w", err)
	}

	compiledSchema, err := compiler.Compile(schemaURI)
	if err != nil {
		return nil, fmt.Errorf("failed to compile schema: %w", err)
	}

	// Parse the IR JSON
	var irData any
	if err := json.Unmarshal(data, &irData); err != nil {
		return &Result{
			Valid:   false,
			Version: version,
			Path:    sourcePath,
			Errors:  []string{fmt.Sprintf("invalid JSON: %v", err)},
		}, nil
	}

	// Validate against the schema
	validationErr := compiledSchema.Validate(irData)
	if validationErr != nil {
		var validationErrors []string
		var vErr *jsonschema.ValidationError
		if errors.As(validationErr, &vErr) {
			validationErrors = collectValidationErrors(vErr)
		} else {
			validationErrors = []string{validationErr.Error()}
		}

		return &Result{
			Valid:   false,
			Version: version,
			Path:    sourcePath,
			Errors:  validationErrors,
			RawData: irData,
		}, nil
	}

	return &Result{
		Valid:   true,
		Version: version,
		Path:    sourcePath,
		RawData: irData,
	}, nil
}

// detectVersion extracts the formatVersion from the IR JSON.
func detectVersion(data []byte) (int, error) {
	var partial struct {
		FormatVersion int `json:"formatVersion"`
	}

	if err := json.Unmarshal(data, &partial); err != nil {
		return 0, fmt.Errorf("failed to parse JSON: %w", err)
	}

	if partial.FormatVersion < 1 || partial.FormatVersion > 3 {
		return 0, fmt.Errorf("invalid formatVersion: %d (expected 1, 2, or 3)", partial.FormatVersion)
	}

	return partial.FormatVersion, nil
}

// collectValidationErrors extracts error messages from the validation error.
func collectValidationErrors(err *jsonschema.ValidationError) []string {
	// Simply return the error message which contains all validation details
	return []string{err.Error()}
}

// FindIRFile finds the morphir.ir.json file starting from the given path.
// If path is a directory, it searches for morphir.ir.json within it.
// If path is a file, it uses that file directly.
func FindIRFile(path string) (string, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", fmt.Errorf("path not found: %w", err)
	}

	if !info.IsDir() {
		return path, nil
	}

	// Search for morphir.ir.json in the directory
	irPath := filepath.Join(path, "morphir.ir.json")
	if _, err := os.Stat(irPath); err == nil {
		return irPath, nil
	}

	return "", fmt.Errorf("morphir.ir.json not found in %s", path)
}
