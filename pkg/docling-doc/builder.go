package docling

// Builder provides an efficient way to incrementally build a DoclingDocument.
// It uses a mutable internal state to avoid allocations during construction,
// then produces an immutable DoclingDocument when Build() is called.
//
// This is useful when you need to build documents with many items without
// the overhead of creating intermediate immutable copies.
//
// Example:
//
//	doc := docling.NewBuilder("Report").
//	    AddTextItem(docling.Ref("intro"), "Introduction text").
//	    AddTextItem(docling.Ref("body"), "Main content").
//	    WithMetadata("author", "John Doe").
//	    Build()
type Builder struct {
	name     string
	items    map[Ref]Item
	body     *Ref
	pages    map[int]PageInfo
	metadata Metadata
}

// NewBuilder creates a new document builder with the given name.
func NewBuilder(name string) *Builder {
	return &Builder{
		name:     name,
		items:    make(map[Ref]Item),
		body:     nil,
		pages:    make(map[int]PageInfo),
		metadata: NewMetadata(),
	}
}

// NewBuilderFrom creates a new builder initialized with an existing document.
// This allows you to modify an existing document efficiently.
func NewBuilderFrom(doc DoclingDocument) *Builder {
	b := &Builder{
		name:     doc.name,
		items:    make(map[Ref]Item, len(doc.items)),
		pages:    make(map[int]PageInfo, len(doc.pages)),
		metadata: make(Metadata, len(doc.metadata)),
	}

	// Copy items
	for k, v := range doc.items {
		b.items[k] = v
	}

	// Copy pages
	for k, v := range doc.pages {
		b.pages[k] = v
	}

	// Copy metadata
	for k, v := range doc.metadata {
		b.metadata[k] = v
	}

	// Copy body reference
	if doc.body != nil {
		bodyRef := *doc.body
		b.body = &bodyRef
	}

	return b
}

// WithName sets the document name. Returns the builder for chaining.
func (b *Builder) WithName(name string) *Builder {
	b.name = name
	return b
}

// AddItem adds an item to the document. Returns the builder for chaining.
func (b *Builder) AddItem(item Item) *Builder {
	b.items[item.SelfRef()] = item
	return b
}

// AddTextItem creates and adds a text item. Returns the builder for chaining.
func (b *Builder) AddTextItem(ref Ref, text string) *Builder {
	item := NewTextItem(ref, text)
	return b.AddItem(item)
}

// AddTableItem creates and adds a table item. Returns the builder for chaining.
func (b *Builder) AddTableItem(ref Ref, numRows, numCols int) *Builder {
	item := NewTableItem(ref, numRows, numCols)
	return b.AddItem(item)
}

// AddPictureItem creates and adds a picture item. Returns the builder for chaining.
func (b *Builder) AddPictureItem(ref Ref, mimeType string) *Builder {
	item := NewPictureItem(ref, mimeType)
	return b.AddItem(item)
}

// AddPictureItemWithData creates and adds a picture item with image data.
// Returns the builder for chaining.
func (b *Builder) AddPictureItemWithData(ref Ref, mimeType string, data []byte) *Builder {
	item := NewPictureItem(ref, mimeType).WithImageData(data)
	return b.AddItem(item)
}

// AddNodeItem creates and adds a node item. Returns the builder for chaining.
func (b *Builder) AddNodeItem(ref Ref, label ItemLabel) *Builder {
	item := NewNodeItem(ref, label)
	return b.AddItem(item)
}

// AddGroupItem creates and adds a group item. Returns the builder for chaining.
func (b *Builder) AddGroupItem(ref Ref, label ItemLabel) *Builder {
	item := NewGroupItem(ref, label)
	return b.AddItem(item)
}

// RemoveItem removes an item from the document. Returns the builder for chaining.
func (b *Builder) RemoveItem(ref Ref) *Builder {
	delete(b.items, ref)
	return b
}

// WithBody sets the body root reference. Returns the builder for chaining.
func (b *Builder) WithBody(ref Ref) *Builder {
	b.body = &ref
	return b
}

// AddPage adds page information. Returns the builder for chaining.
func (b *Builder) AddPage(page PageInfo) *Builder {
	b.pages[page.Number] = page
	return b
}

// AddPageSimple adds page information with just dimensions.
// Returns the builder for chaining.
func (b *Builder) AddPageSimple(pageNum int, width, height float64) *Builder {
	page := PageInfo{
		Number: pageNum,
		Width:  width,
		Height: height,
		Meta:   NewMetadata(),
	}
	return b.AddPage(page)
}

// WithMetadata adds metadata to the document. Returns the builder for chaining.
func (b *Builder) WithMetadata(key string, value interface{}) *Builder {
	b.metadata[key] = value
	return b
}

// Build produces an immutable DoclingDocument from the builder state.
// The builder can be reused after calling Build().
func (b *Builder) Build() DoclingDocument {
	doc := DoclingDocument{
		name:     b.name,
		items:    make(map[Ref]Item, len(b.items)),
		pages:    make(map[int]PageInfo, len(b.pages)),
		metadata: make(Metadata, len(b.metadata)),
	}

	// Copy items
	for k, v := range b.items {
		doc.items[k] = v
	}

	// Copy pages
	for k, v := range b.pages {
		doc.pages[k] = v
	}

	// Copy metadata
	for k, v := range b.metadata {
		doc.metadata[k] = v
	}

	// Copy body reference
	if b.body != nil {
		bodyRef := *b.body
		doc.body = &bodyRef
	}

	return doc
}

// Reset clears all builder state, allowing it to be reused for a new document.
func (b *Builder) Reset(name string) *Builder {
	b.name = name
	b.items = make(map[Ref]Item)
	b.body = nil
	b.pages = make(map[int]PageInfo)
	b.metadata = NewMetadata()
	return b
}

// ItemCount returns the current number of items in the builder.
func (b *Builder) ItemCount() int {
	return len(b.items)
}

// PageCount returns the current number of pages in the builder.
func (b *Builder) PageCount() int {
	return len(b.pages)
}

// HasItem checks if an item with the given reference exists in the builder.
func (b *Builder) HasItem(ref Ref) bool {
	_, exists := b.items[ref]
	return exists
}

// GetItem retrieves an item by reference from the builder.
// Returns nil if the item doesn't exist.
func (b *Builder) GetItem(ref Ref) Item {
	return b.items[ref]
}
