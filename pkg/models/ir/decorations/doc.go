// Package decorations provides the core domain model for Morphir decorations.
//
// Decorations allow users to attach additional metadata to Morphir IR elements
// (types, values, modules) that cannot be captured in the source language.
// The metadata is stored in sidecar files and its shape is defined using
// Morphir IR itself.
//
// This package defines the core domain types for decorations:
//   - DecorationIR: A loaded decoration schema IR
//   - DecorationValue: A decoration value attached to an IR node
//   - DecorationConfig: Configuration for a decoration (moved from config package)
//
// The decoration processing logic (loading, validation, file I/O) lives in
// pkg/tooling/decorations.
package decorations
