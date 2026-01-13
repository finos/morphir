package decorations

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	ir "github.com/finos/morphir/pkg/models/ir"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

// LoadDecorationValues loads decoration values from a JSON file.
//
// The file should contain a JSON object where:
//   - Keys are NodePath strings (e.g., "My.Package:Foo:bar" or "My.Package:Foo")
//   - Values are Morphir IR values encoded as JSON
//
// Example file content:
//
//	{
//	  "My.Package:Foo:bar": { "Literal": [[], "String", "hello"] },
//	  "My.Package:Foo": { "Literal": [[], "String", "module decoration" }
//	}
func LoadDecorationValues(filePath string) (decorationmodels.DecorationValues, error) {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return decorationmodels.EmptyDecorationValues(), fmt.Errorf("resolve file path: %w", err)
	}

	// Check if file exists
	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		// Return empty values if file doesn't exist (not an error)
		return decorationmodels.EmptyDecorationValues(), nil
	}

	data, err := os.ReadFile(absPath)
	if err != nil {
		return decorationmodels.EmptyDecorationValues(), fmt.Errorf("read file: %w", err)
	}

	// Parse as JSON object with string keys
	var rawMap map[string]json.RawMessage
	if err := json.Unmarshal(data, &rawMap); err != nil {
		return decorationmodels.EmptyDecorationValues(), fmt.Errorf("parse JSON: %w", err)
	}

	// Validate that all keys are valid NodePaths, but store as strings
	// (NodePath validation ensures keys are well-formed)
	for keyStr := range rawMap {
		if _, err := ir.ParseNodePath(keyStr); err != nil {
			return decorationmodels.EmptyDecorationValues(), fmt.Errorf("parse NodePath %q: %w", keyStr, err)
		}
	}

	return decorationmodels.NewDecorationValues(rawMap), nil
}

// SaveDecorationValues saves decoration values to a JSON file.
//
// The file will be created or overwritten with a JSON object where:
//   - Keys are NodePath strings
//   - Values are Morphir IR values encoded as JSON
//
// The directory containing the file will be created if it doesn't exist.
func SaveDecorationValues(filePath string, values decorationmodels.DecorationValues) error {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return fmt.Errorf("resolve file path: %w", err)
	}

	// Create directory if it doesn't exist
	dir := filepath.Dir(absPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("create directory: %w", err)
	}

	// Values are already keyed by strings (NodePath.String())
	allValues := values.All()
	rawMap := allValues

	// Marshal to JSON with indentation
	data, err := json.MarshalIndent(rawMap, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal JSON: %w", err)
	}

	// Write to file
	if err := os.WriteFile(absPath, data, 0644); err != nil {
		return fmt.Errorf("write file: %w", err)
	}

	return nil
}

// GetDecorationValueForNodePath retrieves a decoration value for a specific NodePath.
// This is a convenience function that loads the file and returns the value.
func GetDecorationValueForNodePath(filePath string, nodePath ir.NodePath) (json.RawMessage, bool, error) {
	values, err := LoadDecorationValues(filePath)
	if err != nil {
		return nil, false, err
	}
	value, ok := values.Get(nodePath)
	return value, ok, nil
}

// SetDecorationValueForNodePath sets a decoration value for a specific NodePath.
// This loads the existing file, updates/adds the value, and saves it back.
// This is a convenience function - for better performance with multiple updates,
// use LoadDecorationValues, modify the DecorationValues, then SaveDecorationValues.
func SetDecorationValueForNodePath(filePath string, nodePath ir.NodePath, value json.RawMessage) error {
	values, err := LoadDecorationValues(filePath)
	if err != nil {
		return err
	}
	updated := values.WithValue(nodePath, value)
	return SaveDecorationValues(filePath, updated)
}

// RemoveDecorationValueForNodePath removes a decoration value for a specific NodePath.
// This loads the existing file, removes the value, and saves it back.
func RemoveDecorationValueForNodePath(filePath string, nodePath ir.NodePath) error {
	values, err := LoadDecorationValues(filePath)
	if err != nil {
		return err
	}
	updated := values.WithoutValue(nodePath)
	return SaveDecorationValues(filePath, updated)
}
