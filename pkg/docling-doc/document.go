package docling

// DoclingDocument represents a complete Docling document.
// This is immutable and follows functional programming principles.
type DoclingDocument struct {
	name     string
	items    map[Ref]Item
	body     *Ref
	pages    map[int]PageInfo
	metadata Metadata
}

// PageInfo represents information about a page in the document.
type PageInfo struct {
	Number int              `json:"page"`
	Width  float64          `json:"width"`
	Height float64          `json:"height"`
	Meta   Metadata         `json:"metadata,omitempty"`
}

// NewDocument creates a new empty Docling document.
func NewDocument(name string) DoclingDocument {
	return DoclingDocument{
		name:     name,
		items:    make(map[Ref]Item),
		body:     nil,
		pages:    make(map[int]PageInfo),
		metadata: NewMetadata(),
	}
}

// Name returns the document name.
func (d DoclingDocument) Name() string {
	return d.name
}

// Body returns the reference to the body root item.
func (d DoclingDocument) Body() *Ref {
	return d.body
}

// GetItem retrieves an item by its reference.
// Returns nil if the item doesn't exist.
func (d DoclingDocument) GetItem(ref Ref) Item {
	return d.items[ref]
}

// HasItem checks if an item with the given reference exists.
func (d DoclingDocument) HasItem(ref Ref) bool {
	_, exists := d.items[ref]
	return exists
}

// Items returns a copy of all items in the document.
func (d DoclingDocument) Items() map[Ref]Item {
	result := make(map[Ref]Item, len(d.items))
	for k, v := range d.items {
		result[k] = v
	}
	return result
}

// ItemCount returns the number of items in the document.
func (d DoclingDocument) ItemCount() int {
	return len(d.items)
}

// Pages returns a copy of the page information map.
func (d DoclingDocument) Pages() map[int]PageInfo {
	result := make(map[int]PageInfo, len(d.pages))
	for k, v := range d.pages {
		result[k] = v
	}
	return result
}

// GetPage retrieves page information by page number.
func (d DoclingDocument) GetPage(pageNum int) (PageInfo, bool) {
	page, exists := d.pages[pageNum]
	return page, exists
}

// Metadata returns the document metadata.
func (d DoclingDocument) Metadata() Metadata {
	return d.metadata
}

// WithName returns a new document with the given name.
func (d DoclingDocument) WithName(name string) DoclingDocument {
	newDoc := d
	newDoc.name = name
	return newDoc
}

// WithItem returns a new document with an item added or updated.
func (d DoclingDocument) WithItem(item Item) DoclingDocument {
	newDoc := d
	newDoc.items = make(map[Ref]Item, len(d.items)+1)
	for k, v := range d.items {
		newDoc.items[k] = v
	}
	newDoc.items[item.SelfRef()] = item
	return newDoc
}

// WithoutItem returns a new document with an item removed.
func (d DoclingDocument) WithoutItem(ref Ref) DoclingDocument {
	if !d.HasItem(ref) {
		return d
	}
	newDoc := d
	newDoc.items = make(map[Ref]Item, len(d.items)-1)
	for k, v := range d.items {
		if k != ref {
			newDoc.items[k] = v
		}
	}
	return newDoc
}

// WithBody returns a new document with the body root reference set.
func (d DoclingDocument) WithBody(ref Ref) DoclingDocument {
	newDoc := d
	newDoc.body = &ref
	return newDoc
}

// WithPage returns a new document with page information added or updated.
func (d DoclingDocument) WithPage(page PageInfo) DoclingDocument {
	newDoc := d
	newDoc.pages = make(map[int]PageInfo, len(d.pages)+1)
	for k, v := range d.pages {
		newDoc.pages[k] = v
	}
	newDoc.pages[page.Number] = page
	return newDoc
}

// WithMetadata returns a new document with additional metadata.
func (d DoclingDocument) WithMetadata(key string, value interface{}) DoclingDocument {
	newDoc := d
	newDoc.metadata = d.metadata.With(key, value)
	return newDoc
}

// GetChildren returns the child items of a given item.
// Returns an empty slice if the item doesn't exist.
func (d DoclingDocument) GetChildren(ref Ref) []Item {
	item := d.GetItem(ref)
	if item == nil {
		return []Item{}
	}

	childRefs := item.Children()
	result := make([]Item, 0, len(childRefs))
	for _, childRef := range childRefs {
		if child := d.GetItem(childRef); child != nil {
			result = append(result, child)
		}
	}
	return result
}

// GetParent returns the parent item of a given item.
// Returns nil if the item doesn't exist or has no parent.
func (d DoclingDocument) GetParent(ref Ref) Item {
	item := d.GetItem(ref)
	if item == nil {
		return nil
	}

	parentRef := item.Parent()
	if parentRef == nil {
		return nil
	}

	return d.GetItem(*parentRef)
}

// GetSiblings returns the sibling items of a given item.
// Returns an empty slice if the item doesn't exist or has no parent.
func (d DoclingDocument) GetSiblings(ref Ref) []Item {
	item := d.GetItem(ref)
	if item == nil {
		return []Item{}
	}

	parentRef := item.Parent()
	if parentRef == nil {
		return []Item{}
	}

	parent := d.GetItem(*parentRef)
	if parent == nil {
		return []Item{}
	}

	siblings := []Item{}
	for _, childRef := range parent.Children() {
		if childRef != ref {
			if child := d.GetItem(childRef); child != nil {
				siblings = append(siblings, child)
			}
		}
	}
	return siblings
}

// GetDescendants returns all descendant items of a given item (recursive).
func (d DoclingDocument) GetDescendants(ref Ref) []Item {
	var descendants []Item
	var traverse func(Ref)

	traverse = func(currentRef Ref) {
		children := d.GetChildren(currentRef)
		for _, child := range children {
			descendants = append(descendants, child)
			traverse(child.SelfRef())
		}
	}

	traverse(ref)
	return descendants
}

// GetAncestors returns all ancestor items of a given item.
func (d DoclingDocument) GetAncestors(ref Ref) []Item {
	var ancestors []Item
	current := d.GetItem(ref)

	for current != nil {
		parentRef := current.Parent()
		if parentRef == nil {
			break
		}
		parent := d.GetItem(*parentRef)
		if parent == nil {
			break
		}
		ancestors = append(ancestors, parent)
		current = parent
	}

	return ancestors
}

// IsAncestorOf checks if one item is an ancestor of another.
func (d DoclingDocument) IsAncestorOf(ancestor, descendant Ref) bool {
	current := d.GetItem(descendant)

	for current != nil {
		parentRef := current.Parent()
		if parentRef == nil {
			return false
		}
		if *parentRef == ancestor {
			return true
		}
		current = d.GetItem(*parentRef)
	}

	return false
}
