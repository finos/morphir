package domain

import "github.com/Masterminds/semver/v3"

// Package represents a WIT package with namespace, name, version, and contents.
// A package is the top-level organizational unit in WIT, containing interfaces and worlds.
//
// Example WIT:
//
//	package wasi:clocks@0.2.0;
//
//	interface wall-clock {
//	    // ...
//	}
type Package struct {
	// Namespace is the organizational prefix (e.g., "wasi")
	Namespace Namespace

	// Name is the package name (e.g., "clocks")
	Name PackageName

	// Version is optional semantic version (e.g., "0.2.0")
	Version *semver.Version

	// Interfaces contains all interface definitions in this package
	Interfaces []Interface

	// Worlds contains all world definitions in this package
	Worlds []World

	// Uses contains top-level use statements
	Uses []Use

	// Docs contains documentation comments
	Docs Documentation
}

// Ident returns the package identifier in the form "namespace:name" or "namespace:name@version"
func (p Package) Ident() string {
	ident := p.Namespace.String() + ":" + p.Name.String()
	if p.Version != nil {
		ident += "@" + p.Version.String()
	}
	return ident
}
