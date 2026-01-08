package domain

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
)

// Namespace represents a WIT package namespace (e.g., "wasi", "my-org").
// Namespaces must follow kebab-case naming conventions.
type Namespace struct {
	value string
}

// NewNamespace creates a Namespace with validation.
// Returns an error if the namespace is invalid (empty, contains invalid characters, etc.)
func NewNamespace(s string) (Namespace, error) {
	if s == "" {
		return Namespace{}, errors.New("namespace cannot be empty")
	}
	if !isKebabCase(s) {
		return Namespace{}, fmt.Errorf("namespace must be kebab-case: %q", s)
	}
	return Namespace{value: s}, nil
}

// MustNamespace creates a Namespace, panicking if invalid.
// Use only with known-valid string literals.
func MustNamespace(s string) Namespace {
	ns, err := NewNamespace(s)
	if err != nil {
		panic(err)
	}
	return ns
}

// String returns the namespace as a string.
func (n Namespace) String() string {
	return n.value
}

// PackageName represents a WIT package name (e.g., "clocks", "http-types").
// Package names must follow kebab-case naming conventions.
type PackageName struct {
	value string
}

// NewPackageName creates a PackageName with validation.
func NewPackageName(s string) (PackageName, error) {
	if s == "" {
		return PackageName{}, errors.New("package name cannot be empty")
	}
	if !isKebabCase(s) {
		return PackageName{}, fmt.Errorf("package name must be kebab-case: %q", s)
	}
	return PackageName{value: s}, nil
}

// MustPackageName creates a PackageName, panicking if invalid.
func MustPackageName(s string) PackageName {
	pn, err := NewPackageName(s)
	if err != nil {
		panic(err)
	}
	return pn
}

// String returns the package name as a string.
func (p PackageName) String() string {
	return p.value
}

// Identifier represents a WIT identifier (type name, function name, field name, etc.).
// Identifiers must follow kebab-case naming conventions.
type Identifier struct {
	value string
}

// NewIdentifier creates an Identifier with validation.
func NewIdentifier(s string) (Identifier, error) {
	if s == "" {
		return Identifier{}, errors.New("identifier cannot be empty")
	}
	// Allow %id syntax for escaped identifiers
	if strings.HasPrefix(s, "%") {
		return Identifier{value: s}, nil
	}
	if !isKebabCase(s) {
		return Identifier{}, fmt.Errorf("identifier must be kebab-case: %q", s)
	}
	return Identifier{value: s}, nil
}

// MustIdentifier creates an Identifier, panicking if invalid.
func MustIdentifier(s string) Identifier {
	id, err := NewIdentifier(s)
	if err != nil {
		panic(err)
	}
	return id
}

// String returns the identifier as a string.
func (i Identifier) String() string {
	return i.value
}

// Documentation represents documentation comments in WIT.
// Multiple documentation lines are preserved.
type Documentation struct {
	lines []string
}

// NewDocumentation creates Documentation from a single string.
// Multi-line strings are split into separate lines.
func NewDocumentation(s string) Documentation {
	if s == "" {
		return Documentation{}
	}
	lines := strings.Split(s, "\n")
	return Documentation{lines: lines}
}

// NewDocumentationLines creates Documentation from multiple lines.
func NewDocumentationLines(lines []string) Documentation {
	return Documentation{lines: lines}
}

// String returns the documentation as a single string with newlines.
func (d Documentation) String() string {
	return strings.Join(d.lines, "\n")
}

// Lines returns the individual documentation lines.
func (d Documentation) Lines() []string {
	return d.lines
}

// IsEmpty returns true if there is no documentation.
func (d Documentation) IsEmpty() bool {
	return len(d.lines) == 0
}

// kebabCaseRegex matches valid kebab-case identifiers:
// lowercase letters, digits, and hyphens, starting with a letter, not ending with a hyphen
var kebabCaseRegex = regexp.MustCompile(`^[a-z]([a-z0-9-]*[a-z0-9])?$`)

// isKebabCase checks if a string is valid kebab-case
func isKebabCase(s string) bool {
	return kebabCaseRegex.MatchString(s)
}
