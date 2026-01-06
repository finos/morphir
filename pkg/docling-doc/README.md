# Docling Document Package

The `docling-doc` package provides a pure functional Go implementation for working with [Docling documents](https://docling-project.github.io/docling/concepts/docling_document/). Docling is a unified document format designed for AI processing, information extraction, and document analysis.

## Features

- **Immutable Data Structures** - All types follow functional programming principles with value semantics
- **Type-Safe Document Model** - Making illegal states unrepresentable through Go's type system
- **DOM-Like Navigation** - Traverse document hierarchies with parent/child relationships
- **Visitor Pattern** - Push-based processing with functional visitors
- **Functional Traversal** - Map, Filter, Fold, and other higher-order functions
- **JSON/YAML Support** - Serialize and deserialize documents
- **Provenance Tracking** - Track document item origins with bounding boxes and metadata

## Installation

```bash
go get github.com/finos/morphir/pkg/docling-doc
```

## Quick Start

### Creating a Document

```go
import "github.com/finos/morphir/pkg/docling-doc"

// Create a new document
doc := docling.NewDocument("My Document")

// Add a text item
text := docling.NewTextItem(docling.Ref("text1"), "Hello, World!")
doc = doc.WithItem(text)

// Add metadata
doc = doc.WithMetadata("author", "Jane Doe")
```

### Building a Document Tree

```go
// Create hierarchical structure: document -> section -> paragraphs
root := docling.NewGroupItem(docling.Ref("doc"), docling.LabelSectionHeader)
section := docling.NewNodeItem(docling.Ref("section1"), docling.LabelSectionHeader)
para1 := docling.NewTextItem(docling.Ref("para1"), "First paragraph")
para2 := docling.NewTextItem(docling.Ref("para2"), "Second paragraph")

// Set up relationships
root = root.NodeItem.WithChild(docling.Ref("section1"))
section = section.WithParent(docling.Ref("doc")).
    WithChild(docling.Ref("para1")).
    WithChild(docling.Ref("para2"))
para1.DocItem = para1.DocItem.WithParent(docling.Ref("section1"))
para2.DocItem = para2.DocItem.WithParent(docling.Ref("section1"))

// Add to document
doc = doc.WithBody(docling.Ref("doc")).
    WithItem(root).
    WithItem(section).
    WithItem(para1).
    WithItem(para2)
```

### Traversing Documents

#### Using the Visitor Pattern

```go
// Walk the document tree depth-first
err := docling.Walk(doc, docling.Ref("doc"), func(item docling.Item) error {
    fmt.Printf("Item: %s, Label: %s\n", item.SelfRef(), item.Label())
    return nil
})
```

#### Using Functional Operations

```go
// Filter items by label
textItems := docling.FilterByLabel(doc, docling.LabelText)

// Count items
textCount := docling.CountByLabel(doc, docling.LabelText)

// Collect specific items
paragraphs := docling.Collect(doc, func(item docling.Item) bool {
    return item.Label() == docling.LabelParagraph
})

// Find first matching item
firstTable := docling.FindByLabel(doc, docling.LabelTable)

// Check if any item matches
hasImages := docling.Any(doc, func(item docling.Item) bool {
    return item.Label() == docling.LabelPicture
})

// Transform all items
processed := docling.Map(doc, func(item docling.Item) docling.Item {
    // Add metadata to all text items
    if item.Label() == docling.LabelText {
        switch v := item.(type) {
        case docling.TextItem:
            v.DocItem = v.DocItem.WithMetadata("processed", true)
            return v
        }
    }
    return item
})

// Fold/reduce over items
totalLength := docling.Fold(doc, 0, func(acc int, item docling.Item) int {
    if textItem, ok := item.(docling.TextItem); ok {
        return acc + len(textItem.DocItem.Text())
    }
    return acc
})
```

#### Using Channels (Push-Based)

```go
// Iterate over document body
for item := range docling.IterateBody(doc) {
    fmt.Printf("Processing: %s\n", item.SelfRef())
    // Process item
}
```

### DOM-Like Navigation

```go
// Get children of an item
children := doc.GetChildren(docling.Ref("section1"))

// Get parent of an item
parent := doc.GetParent(docling.Ref("para1"))

// Get siblings
siblings := doc.GetSiblings(docling.Ref("para1"))

// Get all descendants (recursive)
descendants := doc.GetDescendants(docling.Ref("doc"))

// Get all ancestors
ancestors := doc.GetAncestors(docling.Ref("para1"))

// Check ancestor relationship
isAncestor := doc.IsAncestorOf(docling.Ref("doc"), docling.Ref("para1"))
```

### Working with Different Item Types

#### Text Items

```go
text := docling.NewTextItem(docling.Ref("text1"), "Sample text")
fmt.Println(text.DocItem.Text())
```

#### Table Items

```go
table := docling.NewTableItem(docling.Ref("table1"), 5, 3) // 5 rows, 3 columns
fmt.Printf("Table: %d rows x %d cols\n", table.NumRows(), table.NumCols())
```

#### Picture Items

```go
picture := docling.NewPictureItem(docling.Ref("pic1"), "image/png")
imageData := []byte{...} // Image bytes
picture = picture.WithImageData(imageData)
```

### Adding Provenance Information

```go
// Create bounding box for layout information
bbox := docling.NewBoundingBox(10, 20, 100, 50, 1) // left, top, width, height, page

// Create provenance
prov := docling.NewProvenanceItem(1).
    WithBoundingBox(bbox).
    WithCharRange(0, 10).
    WithMetadata("source", "PDF")

// Add to item
text := docling.NewTextItem(docling.Ref("text1"), "Hello")
text.DocItem = text.DocItem.WithProvenance(prov)
```

### Serialization

#### JSON

```go
// Serialize to JSON
jsonData, err := docling.ToJSON(doc)
if err != nil {
    log.Fatal(err)
}

// With indentation
jsonData, err = docling.ToJSONIndent(doc, "", "  ")

// Deserialize from JSON
doc2, err := docling.FromJSON(jsonData)
if err != nil {
    log.Fatal(err)
}
```

#### YAML

```go
// Serialize to YAML
yamlData, err := docling.ToYAML(doc)
if err != nil {
    log.Fatal(err)
}

// Note: YAML deserialization support is planned for a future release
```

## Core Types

### DoclingDocument

The main document container with:
- **Name** - Document name/title
- **Items** - Map of all items by reference
- **Body** - Reference to root content item
- **Pages** - Page layout information
- **Metadata** - Document-level metadata

### Item Interface

All document items implement this interface:
- `SelfRef() Ref` - Unique reference
- `Parent() *Ref` - Parent reference
- `Children() []Ref` - Child references
- `Label() ItemLabel` - Item type
- `Provenance() []ProvenanceItem` - Origin information
- `Meta() Metadata` - Item metadata

### Concrete Item Types

- **NodeItem** - Base node with tree structure
- **DocItem** - Content item with text
- **TextItem** - Text content
- **TableItem** - Table with rows/columns
- **PictureItem** - Image with MIME type and data
- **GroupItem** - Logical grouping (sections, chapters)

### Item Labels

Standard labels from the Docling specification:
- `LabelText`, `LabelTitle`, `LabelParagraph`
- `LabelSectionHeader`, `LabelList`, `LabelListItem`
- `LabelTable`, `LabelPicture`, `LabelCode`
- `LabelFormula`, `LabelKeyValue`, `LabelForm`
- `LabelFootnote`, `LabelCaption`
- `LabelPageHeader`, `LabelPageFooter`
- `LabelCheckbox`, `LabelRadioButton`

## Functional Programming Principles

This package strictly follows functional programming principles:

### Immutability

All types are immutable. Methods that appear to "modify" data actually return new instances:

```go
doc := docling.NewDocument("Test")
doc2 := doc.WithMetadata("author", "Alice") // doc is unchanged
```

### Pure Functions

All transformation functions are pure - they don't modify input and have no side effects:

```go
filtered := docling.FilterByLabel(doc, docling.LabelText) // doc is unchanged
```

### Value Semantics

Types use value semantics - copying is safe and expected:

```go
meta1 := docling.NewMetadata()
meta2 := meta1.With("key", "value") // meta1 is unchanged
```

### Functional Composition

Functions compose naturally:

```go
textItems := docling.FilterByLabel(doc, docling.LabelText)
count := docling.Count(textItems, func(item docling.Item) bool {
    switch v := item.(type) {
    case docling.TextItem:
        return len(v.DocItem.Text()) > 10
    }
    return false
})
```

## API Reference

### Document Functions

- `NewDocument(name string) DoclingDocument`
- `(d DoclingDocument) WithItem(item Item) DoclingDocument`
- `(d DoclingDocument) WithoutItem(ref Ref) DoclingDocument`
- `(d DoclingDocument) GetItem(ref Ref) Item`
- `(d DoclingDocument) HasItem(ref Ref) bool`

### Traversal Functions

- `Walk(doc DoclingDocument, startRef Ref, visitor Visitor) error`
- `WalkBody(doc DoclingDocument, visitor Visitor) error`
- `WalkAll(doc DoclingDocument, visitor Visitor) error`

### Functional Operations

- `Filter(doc DoclingDocument, predicate func(Item) bool) DoclingDocument`
- `FilterByLabel(doc DoclingDocument, label ItemLabel) DoclingDocument`
- `Map(doc DoclingDocument, transform func(Item) Item) DoclingDocument`
- `Fold[T any](doc DoclingDocument, initial T, fn func(T, Item) T) T`
- `Collect(doc DoclingDocument, predicate func(Item) bool) []Item`
- `CollectByLabel(doc DoclingDocument, label ItemLabel) []Item`
- `Find(doc DoclingDocument, predicate func(Item) bool) Item`
- `FindByLabel(doc DoclingDocument, label ItemLabel) Item`
- `Any(doc DoclingDocument, predicate func(Item) bool) bool`
- `All(doc DoclingDocument, predicate func(Item) bool) bool`
- `Count(doc DoclingDocument, predicate func(Item) bool) int`
- `CountByLabel(doc DoclingDocument, label ItemLabel) int`

### Iterator Functions

- `IterateTree(doc DoclingDocument, startRef Ref) <-chan Item`
- `IterateBody(doc DoclingDocument) <-chan Item`

### Navigation Functions

- `(d DoclingDocument) GetChildren(ref Ref) []Item`
- `(d DoclingDocument) GetParent(ref Ref) Item`
- `(d DoclingDocument) GetSiblings(ref Ref) []Item`
- `(d DoclingDocument) GetDescendants(ref Ref) []Item`
- `(d DoclingDocument) GetAncestors(ref Ref) []Item`
- `(d DoclingDocument) IsAncestorOf(ancestor, descendant Ref) bool`

## Testing

The package includes comprehensive unit tests covering:
- Type immutability
- Document operations
- Tree navigation
- Visitor patterns
- Functional operations
- JSON serialization

Run tests:

```bash
cd pkg/docling-doc
go test -v
```

## Contributing

This package follows the Morphir project's functional programming guidelines. When contributing:

1. Maintain immutability - never mutate data
2. Use value semantics - return new instances
3. Write pure functions - no side effects
4. Add comprehensive tests
5. Follow TDD/BDD practices

## References

- [Docling Project](https://docling-project.github.io/docling/)
- [Docling Document Format](https://docling-project.github.io/docling/concepts/docling_document/)
- [Morphir Project](https://github.com/finos/morphir)
- [Morphir Go Implementation](https://github.com/finos/morphir)

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.
