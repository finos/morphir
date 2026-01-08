// Package domain contains domain types for Go code generation.
//
// This package defines the intermediate representation between Morphir IR
// and Go code, providing types that capture Go-specific semantics:
//
//   - Go type declarations (structs, interfaces, type aliases)
//   - Go function signatures and implementations
//   - Go package structure and imports
//   - Go module and workspace configuration
//
// # Purpose
//
// The domain types bridge the gap between Morphir's functional IR and Go's
// imperative, object-oriented design patterns:
//
//  1. Morphir IR → domain types: Adapter pattern
//  2. Domain types → Go code: Emitter pattern
//
// This separation allows for:
//
//   - Clear validation of IR before generation
//   - Testable intermediate representation
//   - Flexible output formatting options
//   - Support for different Go idioms (e.g., error vs result types)
//
// # Domain Model
//
// The domain model includes:
//
//   - Module: A Go package with types and functions
//   - TypeDecl: A Go type declaration (struct, interface, type alias)
//   - FuncDecl: A Go function declaration with signature and body
//   - Import: A Go import statement
//   - Package: A collection of modules with dependencies
//
// # Future Extensions
//
// Planned domain types:
//
//   - Method declarations for types
//   - Interface implementations
//   - Build tags and constraints
//   - Generated code markers
//   - Documentation comments
package domain
