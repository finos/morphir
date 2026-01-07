// Package models provides Morphir IR model types, codecs, and SDK helpers.
//
// The primary entry point is the ir subpackage, which contains the Go data
// structures for the Morphir Intermediate Representation along with JSON
// codecs and versioned schema helpers.
//
// Subpackages:
//   - ir: Core IR types (names, paths, modules, types, values, packages).
//   - ir/codec/json: JSON encoding/decoding for IR values and packages.
//   - ir/schema: Embedded Morphir IR JSON schemas and helpers.
//   - ir/sdk: Standard library helpers expressed in IR.
package models
