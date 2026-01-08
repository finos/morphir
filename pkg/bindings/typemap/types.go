package typemap

import (
	"fmt"
	"strings"
)

// Direction indicates the mapping direction.
type Direction int

const (
	// ToMorphir maps from external type to Morphir IR.
	ToMorphir Direction = iota
	// FromMorphir maps from Morphir IR to external type.
	FromMorphir
)

// String returns the string representation of Direction.
func (d Direction) String() string {
	switch d {
	case ToMorphir:
		return "to_morphir"
	case FromMorphir:
		return "from_morphir"
	default:
		return "unknown"
	}
}

// TypeID is a unique identifier for a type in a binding system.
// Format varies by binding: "u32" for WIT, "int32" for Protobuf, etc.
type TypeID string

// MorphirTypeRef identifies a Morphir IR type.
// It can be either a primitive reference or a fully-qualified name.
type MorphirTypeRef struct {
	// FQName is set for complex types (e.g., "Morphir.SDK:Basics:Int").
	// Format: "PackagePath:ModulePath:localName"
	FQName string

	// PrimitiveKind is set for primitive types that map directly.
	// This is a string like "Int", "Float", "Bool" for SDK types.
	PrimitiveKind string
}

// String returns a string representation of the MorphirTypeRef.
func (r MorphirTypeRef) String() string {
	if r.FQName != "" {
		return r.FQName
	}
	return r.PrimitiveKind
}

// IsEmpty returns true if the reference is not set.
func (r MorphirTypeRef) IsEmpty() bool {
	return r.FQName == "" && r.PrimitiveKind == ""
}

// IsPrimitive returns true if this is a primitive type reference.
func (r MorphirTypeRef) IsPrimitive() bool {
	return r.PrimitiveKind != "" && r.FQName == ""
}

// IsFQName returns true if this is a fully-qualified name reference.
func (r MorphirTypeRef) IsFQName() bool {
	return r.FQName != ""
}

// ParseMorphirTypeRef parses a string into a MorphirTypeRef.
// Supports both FQName format ("Package:Module:name") and primitive names ("Int").
func ParseMorphirTypeRef(s string) (MorphirTypeRef, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return MorphirTypeRef{}, fmt.Errorf("empty type reference")
	}

	// If it contains colons, treat as FQName
	if strings.Contains(s, ":") {
		parts := strings.Split(s, ":")
		if len(parts) != 3 {
			return MorphirTypeRef{}, fmt.Errorf("invalid FQName format %q: expected 'Package:Module:name'", s)
		}
		return MorphirTypeRef{FQName: s}, nil
	}

	// Otherwise treat as primitive kind
	return MorphirTypeRef{PrimitiveKind: s}, nil
}

// TypeMapping defines how an external type maps to/from Morphir IR.
type TypeMapping struct {
	// ExternalType is the identifier in the external system (e.g., "u32", "string").
	ExternalType TypeID

	// MorphirType is the corresponding Morphir IR type reference.
	MorphirType MorphirTypeRef

	// Bidirectional indicates whether this mapping works both directions.
	// When false, only the direction specified by Direction is valid.
	Bidirectional bool

	// Direction is the primary direction (used when Bidirectional is false).
	Direction Direction

	// Priority determines which mapping wins when multiple match.
	// Higher values take precedence. Defaults to 0.
	Priority int

	// Metadata holds binding-specific extra information.
	Metadata map[string]any
}

// ContainerMapping defines mappings for parameterized/container types.
type ContainerMapping struct {
	// ExternalPattern is a pattern like "list", "option", "result".
	// The pattern identifies the container type name without type parameters.
	ExternalPattern string

	// MorphirPattern is the corresponding Morphir pattern like "Morphir.SDK:List:List".
	MorphirPattern string

	// TypeParamCount is the number of type parameters (e.g., 1 for list, 2 for result).
	// Use -1 to indicate variadic (e.g., tuple).
	TypeParamCount int

	// Bidirectional indicates whether this mapping works both directions.
	Bidirectional bool

	// Priority determines precedence.
	Priority int
}

// IsVariadic returns true if this container has variadic type parameters.
func (c ContainerMapping) IsVariadic() bool {
	return c.TypeParamCount < 0
}
