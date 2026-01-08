// Package internal contains internal implementation details for Go code generation.
//
// This package is not part of the public API and may change without notice.
// It contains utilities and helpers used by the golang binding implementation:
//
//   - Name mangling and identifier generation
//   - Code formatting utilities
//   - Template rendering helpers
//   - Type conversion utilities
//
// # Organization
//
// The internal package follows Go conventions:
//
//   - adapter: Converts Morphir IR to domain types
//   - emitter: Generates Go source code from domain types
//   - codegen: Code generation utilities and templates
//   - names: Identifier and name mangling utilities
//
// # Usage
//
// This package should only be imported by the golang binding implementation.
// External users should use the public pipeline API instead.
package internal
