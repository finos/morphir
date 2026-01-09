package ir

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
)

// FQName represents a Morphir IR fully-qualified name:
// (packagePath, modulePath, localName).
//
// JSON encoding (Morphir-compatible): an FQName is encoded as a JSON array of length 3:
// [packagePath, modulePath, localName].
//
// Where:
//   - packagePath is a Path
//   - modulePath is a Path
//   - localName is a Name
//
// This type implements encoding/json's hook methods MarshalJSON and UnmarshalJSON
// to provide custom marshalling/unmarshalling that matches the Morphir IR schemas.
//
// Note: the fields are unexported to preserve immutability/value semantics.
// Use FQNameFromParts to construct and Parts() to retrieve defensive copies.
type FQName struct {
	packagePath Path
	modulePath  Path
	localName   Name
}

// FQNameFromParts constructs an FQName from its component parts.
func FQNameFromParts(packagePath Path, modulePath Path, localName Name) FQName {
	return FQName{packagePath: packagePath, modulePath: modulePath, localName: localName}
}

// PackagePath returns the package path component of this fully-qualified name.
func (f FQName) PackagePath() Path {
	return f.packagePath
}

// ModulePath returns the module path component of this fully-qualified name.
func (f FQName) ModulePath() Path {
	return f.modulePath
}

// LocalName returns the local name component of this fully-qualified name.
func (f FQName) LocalName() Name {
	return f.localName
}

// Parts returns all three components of the fully-qualified name: packagePath, modulePath, and localName.
func (f FQName) Parts() (Path, Path, Name) {
	return f.packagePath, f.modulePath, f.localName
}

// Equal performs structural equality.
func (f FQName) Equal(other FQName) bool {
	return f.packagePath.Equal(other.packagePath) &&
		f.modulePath.Equal(other.modulePath) &&
		f.localName.Equal(other.localName)
}

// String returns the canonical Morphir string form of a fully-qualified name.
//
// Format: PackagePath:ModulePath:localName
// - PackagePath and ModulePath use TitleCase names separated by '.'
// - localName uses camelCase
func (f FQName) String() string {
	return strings.Join(
		[]string{
			f.packagePath.ToString(func(n Name) string { return n.ToTitleCase() }, "."),
			f.modulePath.ToString(func(n Name) string { return n.ToTitleCase() }, "."),
			f.localName.ToCamelCase(),
		},
		":",
	)
}

// ParseFQName parses a canonical Morphir string form of a fully-qualified name.
//
// Expected format: PackagePath:ModulePath:localName
func ParseFQName(s string) (FQName, error) {
	parts := strings.Split(s, ":")
	if len(parts) != 3 {
		return FQName{}, fmt.Errorf("ir.FQName: expected 'PackagePath:ModulePath:localName', got %q", s)
	}
	packagePath := PathFromString(parts[0])
	modulePath := PathFromString(parts[1])
	localName := NameFromString(parts[2])
	return FQNameFromParts(packagePath, modulePath, localName), nil
}

// MarshalJSON implements encoding/json.Marshaler.
func (f FQName) MarshalJSON() ([]byte, error) {
	return json.Marshal([]any{f.packagePath, f.modulePath, f.localName})
}

// UnmarshalJSON implements encoding/json.Unmarshaler.
func (f *FQName) UnmarshalJSON(data []byte) error {
	if f == nil {
		return fmt.Errorf("ir.FQName: UnmarshalJSON on nil receiver")
	}

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return fmt.Errorf("ir.FQName: expected [packagePath, modulePath, localName], got null")
	}

	var raw []json.RawMessage
	if err := json.Unmarshal(trimmed, &raw); err != nil {
		return fmt.Errorf("ir.FQName: expected [packagePath, modulePath, localName]: %w", err)
	}
	if len(raw) != 3 {
		return fmt.Errorf("ir.FQName: expected array of length 3, got %d", len(raw))
	}

	var packagePath Path
	if err := json.Unmarshal(raw[0], &packagePath); err != nil {
		return fmt.Errorf("ir.FQName: invalid packagePath: %w", err)
	}
	var modulePath Path
	if err := json.Unmarshal(raw[1], &modulePath); err != nil {
		return fmt.Errorf("ir.FQName: invalid modulePath: %w", err)
	}
	var localName Name
	if err := json.Unmarshal(raw[2], &localName); err != nil {
		return fmt.Errorf("ir.FQName: invalid localName: %w", err)
	}

	*f = FQNameFromParts(packagePath, modulePath, localName)
	return nil
}
