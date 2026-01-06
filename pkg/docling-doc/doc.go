// Package docling provides types and functions for working with Docling documents.
//
// The Docling document format is a unified representation of rich document structures
// (text, tables, images, metadata, etc.) designed for AI processing, information
// extraction, and document analysis.
//
// This package follows functional programming principles:
//   - Immutable data structures
//   - Pure functions for transformations
//   - Making illegal states unrepresentable
//
// # Document Structure
//
// A Docling document contains:
//   - Hierarchical content items (text, tables, pictures, etc.)
//   - Metadata and provenance information
//   - Page-based layout information
//   - References forming a tree structure
//
// # Usage
//
// Documents can be created, traversed, and transformed using pure functions:
//
//	doc := docling.NewDocument("My Document")
//	doc = docling.AddText(doc, "Hello, World!", 1)
//	
//	// Traverse using visitor pattern
//	docling.Walk(doc, func(item Item) error {
//	    fmt.Println(item.Label())
//	    return nil
//	})
//
// # Serialization
//
// Documents can be serialized to/from JSON and YAML:
//
//	data, err := json.Marshal(doc)
//	var doc DoclingDocument
//	err = json.Unmarshal(data, &doc)
package docling
