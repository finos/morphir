// Package nbformat provides Go types for working with Jupyter Notebook format (nbformat 5.x).
//
// This package enables reading, writing, validating, and transforming Jupyter notebooks
// following functional programming principles: immutability, algebraic data types,
// and composable traversal operations.
//
// # Core Types
//
// The package provides immutable types representing the nbformat specification:
//
//   - [Notebook] - The root container holding cells and metadata
//   - [Cell] - A sealed interface with variants [CodeCell], [MarkdownCell], [RawCell]
//   - [Output] - A sealed interface with variants [StreamOutput], [DisplayDataOutput],
//     [ExecuteResultOutput], [ErrorOutput]
//
// # Sealed Interfaces (Sum Types)
//
// Cell and Output types are implemented as sealed interfaces, ensuring that only
// the defined variants can exist. This enables exhaustive pattern matching via
// the visitor pattern:
//
//	result := nbformat.MatchCell(cell, nbformat.CellCases[string]{
//	    Code:     func(c nbformat.CodeCell) string { return "code" },
//	    Markdown: func(c nbformat.MarkdownCell) string { return "markdown" },
//	    Raw:      func(c nbformat.RawCell) string { return "raw" },
//	})
//
// # Immutability
//
// All types are immutable. Modifications return new instances:
//
//	// Create a new notebook with an additional cell
//	newNotebook := notebook.WithCell(newCell)
//
// # Functional Traversal
//
// The package provides Map, Filter, and Fold operations for transforming notebooks:
//
//	// Transform all code cells
//	transformed := nbformat.MapCells(notebook, func(c nbformat.Cell) nbformat.Cell {
//	    if code, ok := c.(nbformat.CodeCell); ok {
//	        return code.WithSource(transform(code.Source()))
//	    }
//	    return c
//	})
//
// # Fluent Builders
//
// For efficient construction, fluent builders provide a low-allocation alternative:
//
//	notebook := nbformat.NewNotebookBuilder().
//	    WithMetadata(meta).
//	    AddCodeCell("print('hello')").
//	    AddMarkdownCell("# Title").
//	    Build()
//
// # JSON Support
//
// Read and write notebooks in JSON format:
//
//	notebook, err := nbformat.ReadFile("notebook.ipynb")
//	err = nbformat.WriteFile(notebook, "output.ipynb")
//
// # Specification Reference
//
// This package implements nbformat 5.x as documented at:
// https://nbformat.readthedocs.io/en/latest/format_description.html
package nbformat
