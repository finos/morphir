package docling

// Item represents any item in a Docling document.
// This is an interface that all document items implement.
type Item interface {
	// SelfRef returns the unique reference for this item.
	SelfRef() Ref

	// Parent returns the reference to the parent item, if any.
	Parent() *Ref

	// Children returns a copy of the child references.
	Children() []Ref

	// Label returns the type/label of this item.
	Label() ItemLabel

	// Provenance returns provenance information for this item.
	Provenance() []ProvenanceItem

	// Meta returns metadata for this item.
	Meta() Metadata
}

// NodeItem represents a base node in the document tree structure.
// This is immutable and follows value semantics.
type NodeItem struct {
	selfRef  Ref
	parent   *Ref
	children []Ref
	label    ItemLabel
	prov     []ProvenanceItem
	meta     Metadata
}

// NewNodeItem creates a new node item.
func NewNodeItem(ref Ref, label ItemLabel) NodeItem {
	return NodeItem{
		selfRef:  ref,
		parent:   nil,
		children: []Ref{},
		label:    label,
		prov:     []ProvenanceItem{},
		meta:     NewMetadata(),
	}
}

// SelfRef returns the unique reference for this item.
func (n NodeItem) SelfRef() Ref {
	return n.selfRef
}

// Parent returns the reference to the parent item, if any.
func (n NodeItem) Parent() *Ref {
	return n.parent
}

// Children returns a copy of the child references.
func (n NodeItem) Children() []Ref {
	if len(n.children) == 0 {
		return []Ref{}
	}
	// Return a copy to maintain immutability
	result := make([]Ref, len(n.children))
	copy(result, n.children)
	return result
}

// Label returns the type/label of this item.
func (n NodeItem) Label() ItemLabel {
	return n.label
}

// Provenance returns a copy of provenance information for this item.
func (n NodeItem) Provenance() []ProvenanceItem {
	if len(n.prov) == 0 {
		return []ProvenanceItem{}
	}
	result := make([]ProvenanceItem, len(n.prov))
	copy(result, n.prov)
	return result
}

// Meta returns metadata for this item.
func (n NodeItem) Meta() Metadata {
	return n.meta
}

// WithParent returns a new NodeItem with the given parent reference.
func (n NodeItem) WithParent(parent Ref) NodeItem {
	newNode := n
	newNode.parent = &parent
	return newNode
}

// WithChild returns a new NodeItem with an additional child reference.
func (n NodeItem) WithChild(child Ref) NodeItem {
	newNode := n
	newNode.children = make([]Ref, len(n.children)+1)
	copy(newNode.children, n.children)
	newNode.children[len(n.children)] = child
	return newNode
}

// WithChildren returns a new NodeItem with the given child references.
func (n NodeItem) WithChildren(children []Ref) NodeItem {
	newNode := n
	newNode.children = make([]Ref, len(children))
	copy(newNode.children, children)
	return newNode
}

// WithProvenance returns a new NodeItem with additional provenance information.
func (n NodeItem) WithProvenance(prov ProvenanceItem) NodeItem {
	newNode := n
	newNode.prov = make([]ProvenanceItem, len(n.prov)+1)
	copy(newNode.prov, n.prov)
	newNode.prov[len(n.prov)] = prov
	return newNode
}

// WithMetadata returns a new NodeItem with additional metadata.
func (n NodeItem) WithMetadata(key string, value interface{}) NodeItem {
	newNode := n
	newNode.meta = n.meta.With(key, value)
	return newNode
}

// DocItem represents a document content item (text, table, picture, etc.).
// This extends NodeItem with text content.
type DocItem struct {
	NodeItem
	text string
}

// NewDocItem creates a new document item.
func NewDocItem(ref Ref, label ItemLabel, text string) DocItem {
	return DocItem{
		NodeItem: NewNodeItem(ref, label),
		text:     text,
	}
}

// Text returns the text content of this item.
func (d DocItem) Text() string {
	return d.text
}

// WithText returns a new DocItem with the given text content.
func (d DocItem) WithText(text string) DocItem {
	newItem := d
	newItem.text = text
	return newItem
}

// WithParent returns a new DocItem with the given parent reference.
func (d DocItem) WithParent(parent Ref) DocItem {
	newItem := d
	newItem.NodeItem = d.NodeItem.WithParent(parent)
	return newItem
}

// WithChild returns a new DocItem with an additional child reference.
func (d DocItem) WithChild(child Ref) DocItem {
	newItem := d
	newItem.NodeItem = d.NodeItem.WithChild(child)
	return newItem
}

// WithChildren returns a new DocItem with the given child references.
func (d DocItem) WithChildren(children []Ref) DocItem {
	newItem := d
	newItem.NodeItem = d.NodeItem.WithChildren(children)
	return newItem
}

// WithProvenance returns a new DocItem with additional provenance information.
func (d DocItem) WithProvenance(prov ProvenanceItem) DocItem {
	newItem := d
	newItem.NodeItem = d.NodeItem.WithProvenance(prov)
	return newItem
}

// WithMetadata returns a new DocItem with additional metadata.
func (d DocItem) WithMetadata(key string, value interface{}) DocItem {
	newItem := d
	newItem.NodeItem = d.NodeItem.WithMetadata(key, value)
	return newItem
}

// TextItem represents a text content item.
type TextItem struct {
	DocItem
}

// NewTextItem creates a new text item.
func NewTextItem(ref Ref, text string) TextItem {
	return TextItem{
		DocItem: NewDocItem(ref, LabelText, text),
	}
}

// TableItem represents a table content item.
type TableItem struct {
	DocItem
	numRows int
	numCols int
}

// NewTableItem creates a new table item.
func NewTableItem(ref Ref, numRows, numCols int) TableItem {
	return TableItem{
		DocItem: NewDocItem(ref, LabelTable, ""),
		numRows: numRows,
		numCols: numCols,
	}
}

// NumRows returns the number of rows in the table.
func (t TableItem) NumRows() int {
	return t.numRows
}

// NumCols returns the number of columns in the table.
func (t TableItem) NumCols() int {
	return t.numCols
}

// PictureItem represents an image/picture content item.
type PictureItem struct {
	DocItem
	imageData []byte
	mimeType  string
}

// NewPictureItem creates a new picture item.
func NewPictureItem(ref Ref, mimeType string) PictureItem {
	return PictureItem{
		DocItem:   NewDocItem(ref, LabelPicture, ""),
		imageData: []byte{},
		mimeType:  mimeType,
	}
}

// WithImageData returns a new PictureItem with the given image data.
func (p PictureItem) WithImageData(data []byte) PictureItem {
	newItem := p
	newItem.imageData = make([]byte, len(data))
	copy(newItem.imageData, data)
	return newItem
}

// ImageData returns a copy of the image data.
func (p PictureItem) ImageData() []byte {
	if len(p.imageData) == 0 {
		return []byte{}
	}
	result := make([]byte, len(p.imageData))
	copy(result, p.imageData)
	return result
}

// MimeType returns the MIME type of the image.
func (p PictureItem) MimeType() string {
	return p.mimeType
}

// GroupItem represents a logical grouping of items (sections, chapters, etc.).
type GroupItem struct {
	NodeItem
}

// NewGroupItem creates a new group item.
func NewGroupItem(ref Ref, label ItemLabel) GroupItem {
	return GroupItem{
		NodeItem: NewNodeItem(ref, label),
	}
}
