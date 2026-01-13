// Package decorations provides functionality for loading and validating decoration
// schemas and values in Morphir projects.
//
// Decorations allow users to attach additional metadata to Morphir IR elements
// (types, values, modules) that cannot be captured in the source language.
// The metadata is stored in sidecar files and its shape is defined using
// Morphir IR itself.
//
// This package follows functional programming principles:
//   - Immutable data structures
//   - Pure functions where possible
//   - Clear separation of concerns
package decorations
