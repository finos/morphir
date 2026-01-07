// Package ir defines the Morphir Intermediate Representation (IR) data model.
//
// The IR types model names, paths, modules, types, values, and packages in a
// language-agnostic way. These structures are designed to be immutable and
// easily composed, keeping to functional programming principles.
//
// Use this package directly when constructing or inspecting Morphir IR in Go.
// For JSON interoperability with other Morphir tools, see ir/codec/json.
package ir
