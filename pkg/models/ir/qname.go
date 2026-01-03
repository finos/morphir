package ir

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
)

// QName represents a Morphir IR qualified name: (modulePath, localName).
//
// JSON encoding (Morphir-compatible): a QName is encoded as a JSON array
// of length 2: [modulePath, localName].
//
// Where:
//   - modulePath is a Path (JSON: list of Names)
//   - localName is a Name (JSON: list of strings)
//
// This type implements encoding/json's hook methods MarshalJSON and UnmarshalJSON
// to provide custom marshalling/unmarshalling that matches the Morphir IR schemas.
//
// Note: the fields are unexported to preserve immutability/value semantics.
// Use QNameFromParts to construct and Parts() to retrieve defensive copies.
type QName struct {
	modulePath Path
	localName  Name
}

// QNameFromParts constructs a QName from its module path and local name.
func QNameFromParts(modulePath Path, localName Name) QName {
	// Both Path and Name already provide value semantics; copying them is sufficient.
	return QName{modulePath: modulePath, localName: localName}
}

// ModulePath returns the module path.
func (q QName) ModulePath() Path {
	return q.modulePath
}

// LocalName returns the local name.
func (q QName) LocalName() Name {
	return q.localName
}

// Parts returns the QName parts.
func (q QName) Parts() (Path, Name) {
	return q.modulePath, q.localName
}

// Equal performs structural equality.
func (q QName) Equal(other QName) bool {
	return q.modulePath.Equal(other.modulePath) && q.localName.Equal(other.localName)
}

// String returns the canonical Morphir string form of a qualified name.
//
// Format: ModulePath:localName
// - ModulePath uses TitleCase names separated by '.'
// - localName uses camelCase
func (q QName) String() string {
	return strings.Join(
		[]string{
			q.modulePath.ToString(func(n Name) string { return n.ToTitleCase() }, "."),
			q.localName.ToCamelCase(),
		},
		":",
	)
}

// ParseQName parses a canonical Morphir string form of a qualified name.
//
// Expected format: ModulePath:localName
func ParseQName(s string) (QName, error) {
	parts := strings.Split(s, ":")
	if len(parts) != 2 {
		return QName{}, fmt.Errorf("ir.QName: expected 'ModulePath:localName', got %q", s)
	}
	modulePath := PathFromString(parts[0])
	localName := NameFromString(parts[1])
	return QNameFromParts(modulePath, localName), nil
}

// MarshalJSON implements encoding/json.Marshaler.
func (q QName) MarshalJSON() ([]byte, error) {
	return json.Marshal([]any{q.modulePath, q.localName})
}

// UnmarshalJSON implements encoding/json.Unmarshaler.
func (q *QName) UnmarshalJSON(data []byte) error {
	if q == nil {
		return fmt.Errorf("ir.QName: UnmarshalJSON on nil receiver")
	}

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return fmt.Errorf("ir.QName: expected [modulePath, localName], got null")
	}

	var raw []json.RawMessage
	if err := json.Unmarshal(trimmed, &raw); err != nil {
		return fmt.Errorf("ir.QName: expected [modulePath, localName]: %w", err)
	}
	if len(raw) != 2 {
		return fmt.Errorf("ir.QName: expected array of length 2, got %d", len(raw))
	}

	var modulePath Path
	if err := json.Unmarshal(raw[0], &modulePath); err != nil {
		return fmt.Errorf("ir.QName: invalid modulePath: %w", err)
	}
	var localName Name
	if err := json.Unmarshal(raw[1], &localName); err != nil {
		return fmt.Errorf("ir.QName: invalid localName: %w", err)
	}

	*q = QNameFromParts(modulePath, localName)
	return nil
}
