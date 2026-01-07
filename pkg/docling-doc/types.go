package docling

import "encoding/json"

// ItemLabel represents the type of a document item.
// This uses the type-safe enum pattern to make illegal states unrepresentable.
type ItemLabel string

// Standard item labels as defined in the Docling specification.
const (
	LabelText          ItemLabel = "text"
	LabelTitle         ItemLabel = "title"
	LabelSectionHeader ItemLabel = "section_header"
	LabelParagraph     ItemLabel = "paragraph"
	LabelList          ItemLabel = "list"
	LabelListItem      ItemLabel = "list_item"
	LabelTable         ItemLabel = "table"
	LabelPicture       ItemLabel = "picture"
	LabelCode          ItemLabel = "code"
	LabelFormula       ItemLabel = "formula"
	LabelKeyValue      ItemLabel = "key_value"
	LabelForm          ItemLabel = "form"
	LabelFootnote      ItemLabel = "footnote"
	LabelCaption       ItemLabel = "caption"
	LabelPageHeader    ItemLabel = "page_header"
	LabelPageFooter    ItemLabel = "page_footer"
	LabelCheckbox      ItemLabel = "checkbox"
	LabelRadioButton   ItemLabel = "radio_button"
)

// String returns the string representation of the label.
func (l ItemLabel) String() string {
	return string(l)
}

// IsValid checks if the label is a known valid label.
func (l ItemLabel) IsValid() bool {
	switch l {
	case LabelText, LabelTitle, LabelSectionHeader, LabelParagraph,
		LabelList, LabelListItem, LabelTable, LabelPicture,
		LabelCode, LabelFormula, LabelKeyValue, LabelForm,
		LabelFootnote, LabelCaption, LabelPageHeader, LabelPageFooter,
		LabelCheckbox, LabelRadioButton:
		return true
	default:
		return false
	}
}

// Ref represents a reference to an item in the document.
// It's an immutable identifier that points to a specific item.
type Ref string

// String returns the string representation of the reference.
func (r Ref) String() string {
	return string(r)
}

// IsEmpty checks if the reference is empty.
func (r Ref) IsEmpty() bool {
	return r == ""
}

// Equal checks if two references are equal.
func (r Ref) Equal(other Ref) bool {
	return r == other
}

// BoundingBox represents the geometric location of an item on a page.
// This is immutable and follows value semantics.
type BoundingBox struct {
	Left   float64 `json:"l"`
	Top    float64 `json:"t"`
	Width  float64 `json:"w"`
	Height float64 `json:"h"`
	Page   int     `json:"page"`
}

// NewBoundingBox creates a new bounding box with the given coordinates.
func NewBoundingBox(left, top, width, height float64, page int) BoundingBox {
	return BoundingBox{
		Left:   left,
		Top:    top,
		Width:  width,
		Height: height,
		Page:   page,
	}
}

// Right returns the right coordinate of the bounding box.
func (b BoundingBox) Right() float64 {
	return b.Left + b.Width
}

// Bottom returns the bottom coordinate of the bounding box.
func (b BoundingBox) Bottom() float64 {
	return b.Top + b.Height
}

// Contains checks if a point is within the bounding box.
func (b BoundingBox) Contains(x, y float64) bool {
	return x >= b.Left && x <= b.Right() &&
		y >= b.Top && y <= b.Bottom()
}

// Intersects checks if this bounding box intersects with another.
func (b BoundingBox) Intersects(other BoundingBox) bool {
	if b.Page != other.Page {
		return false
	}
	return !(b.Right() < other.Left ||
		other.Right() < b.Left ||
		b.Bottom() < other.Top ||
		other.Bottom() < b.Top)
}

// ProvenanceItem represents information about where an item came from.
// This is immutable.
type ProvenanceItem struct {
	BBox      *BoundingBox           `json:"bbox,omitempty"`
	Page      int                    `json:"page,omitempty"`
	CharStart int                    `json:"charstart,omitempty"`
	CharEnd   int                    `json:"charend,omitempty"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

// NewProvenanceItem creates a new provenance item.
func NewProvenanceItem(page int) ProvenanceItem {
	return ProvenanceItem{
		Page:     page,
		Metadata: make(map[string]interface{}),
	}
}

// WithBoundingBox returns a new provenance item with the given bounding box.
func (p ProvenanceItem) WithBoundingBox(bbox BoundingBox) ProvenanceItem {
	newProv := p
	newProv.BBox = &bbox
	return newProv
}

// WithCharRange returns a new provenance item with the given character range.
func (p ProvenanceItem) WithCharRange(start, end int) ProvenanceItem {
	newProv := p
	newProv.CharStart = start
	newProv.CharEnd = end
	return newProv
}

// WithMetadata returns a new provenance item with additional metadata.
func (p ProvenanceItem) WithMetadata(key string, value interface{}) ProvenanceItem {
	newProv := p
	// Create a new map to maintain immutability
	if p.Metadata != nil {
		newProv.Metadata = make(map[string]interface{}, len(p.Metadata)+1)
		for k, v := range p.Metadata {
			newProv.Metadata[k] = v
		}
	} else {
		newProv.Metadata = make(map[string]interface{})
	}
	newProv.Metadata[key] = value
	return newProv
}

// Metadata represents arbitrary metadata associated with an item.
// This follows the value semantics pattern.
type Metadata map[string]interface{}

// NewMetadata creates a new empty metadata map.
func NewMetadata() Metadata {
	return make(Metadata)
}

// With returns a new Metadata with the given key-value pair added.
func (m Metadata) With(key string, value interface{}) Metadata {
	newMeta := make(Metadata, len(m)+1)
	for k, v := range m {
		newMeta[k] = v
	}
	newMeta[key] = value
	return newMeta
}

// Get retrieves a value from the metadata.
func (m Metadata) Get(key string) (interface{}, bool) {
	val, ok := m[key]
	return val, ok
}

// GetString retrieves a string value from the metadata.
func (m Metadata) GetString(key string) (string, bool) {
	val, ok := m[key]
	if !ok {
		return "", false
	}
	str, ok := val.(string)
	return str, ok
}

// GetInt retrieves an int value from the metadata.
func (m Metadata) GetInt(key string) (int, bool) {
	val, ok := m[key]
	if !ok {
		return 0, false
	}
	// Handle both int and float64 (from JSON)
	switch v := val.(type) {
	case int:
		return v, true
	case float64:
		return int(v), true
	default:
		return 0, false
	}
}

// MarshalJSON implements json.Marshaler.
func (m Metadata) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}(m))
}

// UnmarshalJSON implements json.Unmarshaler.
func (m *Metadata) UnmarshalJSON(data []byte) error {
	var result map[string]interface{}
	if err := json.Unmarshal(data, &result); err != nil {
		return err
	}
	*m = Metadata(result)
	return nil
}
