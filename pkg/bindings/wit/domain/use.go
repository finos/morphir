package domain

import "github.com/Masterminds/semver/v3"

// Use represents a WIT use statement for importing types or interfaces.
//
// Example WIT:
//
//	use wasi:http/types@1.0.0.{request, response};
//	use other-interface.{type-a, type-b as renamed};
type Use struct {
	// Path identifies what is being imported
	Path UsePath

	// Items are the specific types/functions being imported
	Items []UseItem

	// Alias is for top-level use statements (use foo as bar)
	Alias *Identifier
}

// UsePath represents the path to an interface or package being imported.
// This is a discriminated union - either local or external reference.
type UsePath interface {
	usePathMarker()
}

// LocalUsePath references an interface in the same package.
//
// Example: use other-interface.{type-a}
type LocalUsePath struct {
	Interface Identifier
}

func (LocalUsePath) usePathMarker() {}

// ExternalUsePath references an interface from another package.
//
// Example: use wasi:http/types@1.0.0.{request}
type ExternalUsePath struct {
	Namespace Namespace
	Package   PackageName
	Interface *Identifier     // nil for package-level imports
	Version   *semver.Version // nil if no version specified
}

func (ExternalUsePath) usePathMarker() {}

// UseItem represents a single item being imported in a use statement.
//
// Example: type-a as renamed-type
type UseItem struct {
	Name  Identifier
	Alias *Identifier // nil if no alias
}
