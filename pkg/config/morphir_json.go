// Package config provides configuration loading for Morphir projects.
package config

import (
	"encoding/json"
	"errors"
	"os"
)

// DecorationConfig represents a single decoration configuration.
//
// Example:
//
//	{
//	    "displayName": "My Amazing Decoration",
//	    "ir": "decorations/my/morphir-ir.json",
//	    "entryPoint": "My.Amazing.Decoration:Foo:Shape",
//	    "storageLocation": "my-decoration-values.json"
//	}
type DecorationConfig struct {
	displayName     string
	ir              string
	entryPoint      string
	storageLocation string
}

// DisplayName returns the display name of the decoration.
func (d DecorationConfig) DisplayName() string {
	return d.displayName
}

// IR returns the path to the decoration IR file.
func (d DecorationConfig) IR() string {
	return d.ir
}

// EntryPoint returns the fully-qualified name (FQName) of the decoration type.
// Format: PackageName:ModuleName:TypeName
func (d DecorationConfig) EntryPoint() string {
	return d.entryPoint
}

// StorageLocation returns the path where decoration values are stored.
func (d DecorationConfig) StorageLocation() string {
	return d.storageLocation
}

// MorphirJSON represents the legacy morphir.json configuration format
// used by finos/morphir-elm.
//
// Example:
//
//	{
//	    "name": "My.Package",
//	    "sourceDirectory": "src",
//	    "exposedModules": ["Foo", "Bar"],
//	    "decorations": {
//	        "myDecoration": {
//	            "displayName": "My Amazing Decoration",
//	            "ir": "decorations/my/morphir-ir.json",
//	            "entryPoint": "My.Amazing.Decoration:Foo:Shape",
//	            "storageLocation": "my-decoration-values.json"
//	        }
//	    }
//	}
type MorphirJSON struct {
	name            string
	sourceDirectory string
	exposedModules  []string
	decorations     map[string]DecorationConfig
}

// Name returns the package name.
func (m MorphirJSON) Name() string {
	return m.name
}

// SourceDirectory returns the source directory path.
func (m MorphirJSON) SourceDirectory() string {
	return m.sourceDirectory
}

// ExposedModules returns the list of exposed modules.
// Returns a defensive copy to preserve immutability.
func (m MorphirJSON) ExposedModules() []string {
	if len(m.exposedModules) == 0 {
		return nil
	}
	result := make([]string, len(m.exposedModules))
	copy(result, m.exposedModules)
	return result
}

// Decorations returns the map of decoration configurations.
// Returns a defensive copy to preserve immutability.
func (m MorphirJSON) Decorations() map[string]DecorationConfig {
	if len(m.decorations) == 0 {
		return nil
	}
	result := make(map[string]DecorationConfig, len(m.decorations))
	for k, v := range m.decorations {
		result[k] = v
	}
	return result
}

// decorationConfigRaw is the internal struct for JSON unmarshaling of decoration configs.
type decorationConfigRaw struct {
	DisplayName     string `json:"displayName"`
	IR              string `json:"ir"`
	EntryPoint      string `json:"entryPoint"`
	StorageLocation string `json:"storageLocation"`
}

// morphirJSONRaw is the internal struct for JSON unmarshaling.
type morphirJSONRaw struct {
	Name            string                         `json:"name"`
	SourceDirectory string                         `json:"sourceDirectory"`
	ExposedModules  []string                       `json:"exposedModules"`
	Decorations     map[string]decorationConfigRaw `json:"decorations"`
}

// Validation errors for MorphirJSON.
var (
	ErrMorphirJSONEmptyName            = errors.New("morphir.json: name is required")
	ErrMorphirJSONEmptySourceDirectory = errors.New("morphir.json: sourceDirectory is required")
)

// ParseMorphirJSON parses morphir.json content from bytes.
func ParseMorphirJSON(data []byte) (MorphirJSON, error) {
	var raw morphirJSONRaw
	if err := json.Unmarshal(data, &raw); err != nil {
		return MorphirJSON{}, err
	}

	return validateAndConvert(raw)
}

// LoadMorphirJSON reads and parses a morphir.json file from the given path.
func LoadMorphirJSON(path string) (MorphirJSON, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return MorphirJSON{}, err
	}

	return ParseMorphirJSON(data)
}

// validateAndConvert validates the raw JSON and converts to MorphirJSON.
func validateAndConvert(raw morphirJSONRaw) (MorphirJSON, error) {
	if raw.Name == "" {
		return MorphirJSON{}, ErrMorphirJSONEmptyName
	}
	if raw.SourceDirectory == "" {
		return MorphirJSON{}, ErrMorphirJSONEmptySourceDirectory
	}

	// Copy exposed modules for immutability
	var modules []string
	if len(raw.ExposedModules) > 0 {
		modules = make([]string, len(raw.ExposedModules))
		copy(modules, raw.ExposedModules)
	}

	// Copy decorations for immutability
	var decorations map[string]DecorationConfig
	if len(raw.Decorations) > 0 {
		decorations = make(map[string]DecorationConfig, len(raw.Decorations))
		for k, v := range raw.Decorations {
			decorations[k] = DecorationConfig{
				displayName:     v.DisplayName,
				ir:              v.IR,
				entryPoint:      v.EntryPoint,
				storageLocation: v.StorageLocation,
			}
		}
	}

	return MorphirJSON{
		name:            raw.Name,
		sourceDirectory: raw.SourceDirectory,
		exposedModules:  modules,
		decorations:     decorations,
	}, nil
}

// ToProjectSection converts MorphirJSON to a ProjectSection.
// Since morphir.json names are always Elm-style module prefixes,
// both name and modulePrefix are set to the same value.
func (m MorphirJSON) ToProjectSection() ProjectSection {
	return ProjectSection{
		name:            m.name,
		version:         "", // Not specified in morphir.json
		sourceDirectory: m.sourceDirectory,
		exposedModules:  m.ExposedModules(), // Use getter for defensive copy
		modulePrefix:    m.name,             // Elm-style name doubles as prefix
		decorations:     m.Decorations(),    // Use getter for defensive copy
	}
}
