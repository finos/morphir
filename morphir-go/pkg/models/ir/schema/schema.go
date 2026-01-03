// Package schema provides embedded Morphir IR JSON schemas for validation.
//
// This package embeds the official Morphir IR JSON schemas (in YAML format)
// that define the structure of Morphir IR distributions. These schemas can be
// used to validate morphir.ir.json files against the specification.
//
// Three schema versions are provided:
//   - v1: Original format with lowercase tags and array-based module structure
//   - v2: Transitional format with capitalized type tags but lowercase value tags
//   - v3: Current format with fully capitalized tags throughout
package schema

import (
	"embed"
	"fmt"
)

//go:embed morphir-ir-v1.yaml morphir-ir-v2.yaml morphir-ir-v3.yaml
var schemaFS embed.FS

// Version represents a Morphir IR format version.
type Version int

const (
	// V1 is the original Morphir IR format (lowercase tags, array-based modules).
	V1 Version = 1
	// V2 is the transitional format (capitalized type tags, lowercase value tags).
	V2 Version = 2
	// V3 is the current format (fully capitalized tags).
	V3 Version = 3
)

// String returns the string representation of the version.
func (v Version) String() string {
	return fmt.Sprintf("v%d", v)
}

// schemaFiles maps versions to their schema filenames.
var schemaFiles = map[Version]string{
	V1: "morphir-ir-v1.yaml",
	V2: "morphir-ir-v2.yaml",
	V3: "morphir-ir-v3.yaml",
}

// GetSchema returns the embedded schema for the specified version.
// Returns an error if the version is not supported.
func GetSchema(version Version) ([]byte, error) {
	filename, ok := schemaFiles[version]
	if !ok {
		return nil, fmt.Errorf("unsupported schema version: %d", version)
	}

	data, err := schemaFS.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("failed to read schema file %s: %w", filename, err)
	}

	return data, nil
}

// GetSchemaV1 returns the embedded v1 schema.
func GetSchemaV1() ([]byte, error) {
	return GetSchema(V1)
}

// GetSchemaV2 returns the embedded v2 schema.
func GetSchemaV2() ([]byte, error) {
	return GetSchema(V2)
}

// GetSchemaV3 returns the embedded v3 schema.
func GetSchemaV3() ([]byte, error) {
	return GetSchema(V3)
}

// LatestVersion returns the latest supported schema version.
func LatestVersion() Version {
	return V3
}

// SupportedVersions returns all supported schema versions.
func SupportedVersions() []Version {
	return []Version{V1, V2, V3}
}

// GetLatestSchema returns the embedded schema for the latest version.
func GetLatestSchema() ([]byte, error) {
	return GetSchema(LatestVersion())
}
