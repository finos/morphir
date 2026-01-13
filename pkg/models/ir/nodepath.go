package ir

import (
	"encoding/json"
	"fmt"
	"strings"
)

// NodePath represents a path to a node within the Morphir IR tree.
//
// NodePath provides a way to uniquely identify any node in the IR, including:
// - Types: PackageName:ModuleName:TypeName (FQName)
// - Values: PackageName:ModuleName:ValueName (FQName)
// - Modules: PackageName:ModuleName (QualifiedModuleName)
// - Nested nodes: Additional path segments for nested structures
//
// This is used for decoration attachment and other node identification needs.
//
// JSON encoding: NodePath is encoded as a string in the format:
//
//	"PackageName:ModuleName:LocalName" (for FQName-based paths)
//	"PackageName:ModuleName" (for module paths)
//	"PackageName:ModuleName:LocalName:Segment1:Segment2" (for nested paths)
type NodePath struct {
	packagePath Path
	modulePath  Path
	localName   *Name  // nil for module-level paths
	segments    []Name // Additional segments for nested paths (e.g., field names, indices)
}

// NodePathFromFQName creates a NodePath from an FQName.
// This is the most common case for identifying types and values.
func NodePathFromFQName(fqName FQName) NodePath {
	localName := fqName.LocalName()
	return NodePath{
		packagePath: fqName.PackagePath(),
		modulePath:  fqName.ModulePath(),
		localName:   &localName,
		segments:    nil,
	}
}

// NodePathFromQualifiedModuleName creates a NodePath for a module.
// This identifies a module-level node (no local name).
func NodePathFromQualifiedModuleName(qName QualifiedModuleName) NodePath {
	return NodePath{
		packagePath: qName.PackagePath(),
		modulePath:  qName.ModulePath(),
		localName:   nil,
		segments:    nil,
	}
}

// NodePathFromParts creates a NodePath from its component parts.
// If localName is nil, this represents a module-level path.
func NodePathFromParts(packagePath Path, modulePath Path, localName *Name, segments []Name) NodePath {
	var segmentsCopy []Name
	if len(segments) > 0 {
		segmentsCopy = make([]Name, len(segments))
		copy(segmentsCopy, segments)
	}
	return NodePath{
		packagePath: packagePath,
		modulePath:  modulePath,
		localName:   localName,
		segments:    segmentsCopy,
	}
}

// PackagePath returns the package path component.
func (n NodePath) PackagePath() Path {
	return n.packagePath
}

// ModulePath returns the module path component.
func (n NodePath) ModulePath() Path {
	return n.modulePath
}

// LocalName returns the local name component, or nil if this is a module-level path.
func (n NodePath) LocalName() *Name {
	if n.localName == nil {
		return nil
	}
	// Return defensive copy
	name := *n.localName
	return &name
}

// Segments returns additional path segments for nested nodes.
func (n NodePath) Segments() []Name {
	if len(n.segments) == 0 {
		return nil
	}
	copied := make([]Name, len(n.segments))
	copy(copied, n.segments)
	return copied
}

// ToFQName converts this NodePath to an FQName if it has a local name.
// Returns an error if this is a module-level path or has additional segments.
func (n NodePath) ToFQName() (FQName, error) {
	if n.localName == nil {
		return FQName{}, fmt.Errorf("NodePath: cannot convert module-level path to FQName")
	}
	if len(n.segments) > 0 {
		return FQName{}, fmt.Errorf("NodePath: cannot convert nested path to FQName")
	}
	return FQNameFromParts(n.packagePath, n.modulePath, *n.localName), nil
}

// ToQualifiedModuleName converts this NodePath to a QualifiedModuleName.
// Returns an error if this path has a local name or segments.
func (n NodePath) ToQualifiedModuleName() (QualifiedModuleName, error) {
	if n.localName != nil {
		return QualifiedModuleName{}, fmt.Errorf("NodePath: cannot convert path with local name to QualifiedModuleName")
	}
	if len(n.segments) > 0 {
		return QualifiedModuleName{}, fmt.Errorf("NodePath: cannot convert nested path to QualifiedModuleName")
	}
	return NewQualifiedModuleName(n.packagePath, n.modulePath), nil
}

// Equal performs structural equality.
func (n NodePath) Equal(other NodePath) bool {
	if !n.packagePath.Equal(other.packagePath) {
		return false
	}
	if !n.modulePath.Equal(other.modulePath) {
		return false
	}
	if (n.localName == nil) != (other.localName == nil) {
		return false
	}
	if n.localName != nil && !n.localName.Equal(*other.localName) {
		return false
	}
	if len(n.segments) != len(other.segments) {
		return false
	}
	for i := range n.segments {
		if !n.segments[i].Equal(other.segments[i]) {
			return false
		}
	}
	return true
}

// String returns the canonical string representation of a NodePath.
//
// Format:
//   - Module-level: "PackageName:ModuleName"
//   - Type/Value: "PackageName:ModuleName:LocalName"
//   - Nested: "PackageName:ModuleName:LocalName:Segment1:Segment2"
func (n NodePath) String() string {
	parts := []string{
		n.packagePath.ToString(func(n Name) string { return n.ToTitleCase() }, "."),
		n.modulePath.ToString(func(n Name) string { return n.ToTitleCase() }, "."),
	}
	if n.localName != nil {
		parts = append(parts, n.localName.ToCamelCase())
	}
	for _, seg := range n.segments {
		parts = append(parts, seg.ToCamelCase())
	}
	return strings.Join(parts, ":")
}

// ParseNodePath parses a canonical string representation of a NodePath.
//
// Expected formats:
//   - "PackageName:ModuleName" (module-level)
//   - "PackageName:ModuleName:LocalName" (type/value)
//   - "PackageName:ModuleName:LocalName:Segment1:Segment2" (nested)
func ParseNodePath(s string) (NodePath, error) {
	parts := strings.Split(s, ":")
	if len(parts) < 2 {
		return NodePath{}, fmt.Errorf("NodePath: expected at least 'PackageName:ModuleName', got %q", s)
	}

	packagePath := PathFromString(parts[0])
	modulePath := PathFromString(parts[1])

	if len(parts) == 2 {
		// Module-level path
		return NodePathFromQualifiedModuleName(NewQualifiedModuleName(packagePath, modulePath)), nil
	}

	// Has local name and possibly segments
	localName := NameFromString(parts[2])
	var segments []Name
	if len(parts) > 3 {
		segments = make([]Name, len(parts)-3)
		for i := 3; i < len(parts); i++ {
			segments[i-3] = NameFromString(parts[i])
		}
	}

	return NodePathFromParts(packagePath, modulePath, &localName, segments), nil
}

// MarshalJSON implements encoding/json.Marshaler.
func (n NodePath) MarshalJSON() ([]byte, error) {
	return json.Marshal(n.String())
}

// UnmarshalJSON implements encoding/json.Unmarshaler.
func (n *NodePath) UnmarshalJSON(data []byte) error {
	if n == nil {
		return fmt.Errorf("NodePath: UnmarshalJSON on nil receiver")
	}

	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		return fmt.Errorf("NodePath: expected string, got %T: %w", data, err)
	}

	parsed, err := ParseNodePath(s)
	if err != nil {
		return fmt.Errorf("NodePath: parse error: %w", err)
	}

	*n = parsed
	return nil
}
