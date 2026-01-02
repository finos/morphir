package ir

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
)

// Path represents a Morphir IR Path.
//
// In Morphir IR JSON (morphir-elm `Morphir.IR.Path.Codec`), a path is encoded as a JSON
// array of Names, and each Name is encoded as an array of strings.
//
// This type implements encoding/json's hook methods MarshalJSON and UnmarshalJSON
// to provide custom marshalling/unmarshalling that matches the Morphir IR schemas.
//
// Example JSON:
//
//	[["morphir"],["s","d","k"]]
//
// Note: We keep the underlying slice unexported to preserve immutability/value semantics.
// Use PathFromParts to construct and Parts() to retrieve a defensive copy.
type Path struct {
	parts []Name
}

var pathSeparatorPattern = regexp.MustCompile(`[^\w\s]+`) // Morphir-Elm compatible

// PathFromString translates a string into a Path by splitting it into names along special characters.
//
// This follows morphir-elm's Morphir.IR.Path.fromString behavior:
// - any non-word characters that are not spaces are treated as separators
// - each segment is converted using NameFromString
func PathFromString(s string) Path {
	segments := pathSeparatorPattern.Split(s, -1)
	if len(segments) == 0 {
		return Path{parts: nil}
	}
	parts := make([]Name, 0, len(segments))
	for _, seg := range segments {
		parts = append(parts, NameFromString(seg))
	}
	return PathFromParts(parts)
}

// ToString turns a Path into a string using the specified naming convention and separator.
func (p Path) ToString(nameToString func(Name) string, sep string) string {
	if len(p.parts) == 0 {
		return ""
	}
	out := make([]string, 0, len(p.parts))
	for _, n := range p.parts {
		out = append(out, nameToString(n))
	}
	return strings.Join(out, sep)
}

// HasPrefix checks if prefix is a prefix of p.
func (p Path) HasPrefix(prefix Path) bool {
	if len(prefix.parts) == 0 {
		return true
	}
	if len(p.parts) == 0 {
		return false
	}
	if len(prefix.parts) > len(p.parts) {
		return false
	}
	for i := range prefix.parts {
		if !p.parts[i].Equal(prefix.parts[i]) {
			return false
		}
	}
	return true
}

// PathFromParts constructs a Path from its component Name parts.
// The input slice is defensively copied.
func PathFromParts(parts []Name) Path {
	if len(parts) == 0 {
		return Path{parts: nil}
	}
	copyParts := make([]Name, len(parts))
	copy(copyParts, parts)
	return Path{parts: copyParts}
}

// Parts returns a defensive copy of the path parts.
func (p Path) Parts() []Name {
	if len(p.parts) == 0 {
		return nil
	}
	copyParts := make([]Name, len(p.parts))
	copy(copyParts, p.parts)
	return copyParts
}

// Equal performs structural equality.
func (p Path) Equal(other Path) bool {
	if len(p.parts) != len(other.parts) {
		return false
	}
	for i := range p.parts {
		if !p.parts[i].Equal(other.parts[i]) {
			return false
		}
	}
	return true
}

// MarshalJSON implements encoding/json.Marshaler.
// It encodes the path as a JSON array of names.
func (p Path) MarshalJSON() ([]byte, error) {
	return json.Marshal(p.parts)
}

// UnmarshalJSON implements encoding/json.Unmarshaler.
// It decodes the path from a JSON array of names.
func (p *Path) UnmarshalJSON(data []byte) error {
	if p == nil {
		return fmt.Errorf("ir.Path: UnmarshalJSON on nil receiver")
	}

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return fmt.Errorf("ir.Path: expected array of names, got null")
	}

	var parts []Name
	if err := json.Unmarshal(trimmed, &parts); err != nil {
		return fmt.Errorf("ir.Path: expected array of names: %w", err)
	}

	*p = PathFromParts(parts)
	return nil
}
