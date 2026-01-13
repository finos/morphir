package docling

import (
	"encoding/json"
	"fmt"
)

// jsonDocument represents the JSON structure for serialization.
type jsonDocument struct {
	Name     string                 `json:"name"`
	Items    map[string]jsonItem    `json:"items"`
	Body     *string                `json:"body,omitempty"`
	Pages    map[int]PageInfo       `json:"pages,omitempty"`
	Metadata map[string]interface{} `json:"metadata,omitempty"`
}

// jsonItem represents a generic item for JSON serialization.
type jsonItem struct {
	Type       string                 `json:"type"`
	SelfRef    string                 `json:"self_ref"`
	Parent     *string                `json:"parent,omitempty"`
	Children   []string               `json:"children,omitempty"`
	Label      string                 `json:"label"`
	Provenance []ProvenanceItem       `json:"prov,omitempty"`
	Metadata   map[string]interface{} `json:"meta,omitempty"`
	Text       *string                `json:"text,omitempty"`
	NumRows    *int                   `json:"num_rows,omitempty"`
	NumCols    *int                   `json:"num_cols,omitempty"`
	MimeType   *string                `json:"mime_type,omitempty"`
	ImageData  []byte                 `json:"image_data,omitempty"`
}

// MarshalJSON implements json.Marshaler for DoclingDocument.
func (d DoclingDocument) MarshalJSON() ([]byte, error) {
	jd := jsonDocument{
		Name:     d.name,
		Items:    make(map[string]jsonItem),
		Pages:    d.pages,
		Metadata: d.metadata,
	}

	if d.body != nil {
		bodyStr := d.body.String()
		jd.Body = &bodyStr
	}

	for ref, item := range d.items {
		ji := jsonItem{
			SelfRef:    ref.String(),
			Label:      item.Label().String(),
			Provenance: item.Provenance(),
			Metadata:   item.Meta(),
			Children:   make([]string, 0),
		}

		if parent := item.Parent(); parent != nil {
			parentStr := parent.String()
			ji.Parent = &parentStr
		}

		for _, child := range item.Children() {
			ji.Children = append(ji.Children, child.String())
		}

		// Type-specific serialization
		switch v := item.(type) {
		case TextItem:
			ji.Type = "text"
			text := v.Text()
			ji.Text = &text
		case DocItem:
			ji.Type = "doc"
			text := v.Text()
			ji.Text = &text
		case TableItem:
			ji.Type = "table"
			rows := v.NumRows()
			cols := v.NumCols()
			ji.NumRows = &rows
			ji.NumCols = &cols
		case PictureItem:
			ji.Type = "picture"
			mimeType := v.MimeType()
			ji.MimeType = &mimeType
			ji.ImageData = v.ImageData()
		case GroupItem:
			ji.Type = "group"
		case NodeItem:
			ji.Type = "node"
		default:
			ji.Type = "unknown"
		}

		jd.Items[ref.String()] = ji
	}

	return json.Marshal(jd)
}

// UnmarshalJSON implements json.Unmarshaler for DoclingDocument.
func (d *DoclingDocument) UnmarshalJSON(data []byte) error {
	var jd jsonDocument
	if err := json.Unmarshal(data, &jd); err != nil {
		return fmt.Errorf("failed to unmarshal document: %w", err)
	}

	doc := NewDocument(jd.Name)

	// Unmarshal pages
	for _, page := range jd.Pages {
		doc = doc.WithPage(page)
	}

	// Unmarshal metadata
	if jd.Metadata != nil {
		doc.metadata = Metadata(jd.Metadata)
	}

	// Unmarshal items
	for refStr, ji := range jd.Items {
		ref := Ref(refStr)
		label := ItemLabel(ji.Label)

		var item Item

		switch ji.Type {
		case "text":
			textItem := NewTextItem(ref, "")
			if ji.Text != nil {
				textItem.DocItem = textItem.WithText(*ji.Text)
			}
			item = textItem
		case "doc":
			docItem := NewDocItem(ref, label, "")
			if ji.Text != nil {
				docItem = docItem.WithText(*ji.Text)
			}
			item = docItem
		case "table":
			rows, cols := 0, 0
			if ji.NumRows != nil {
				rows = *ji.NumRows
			}
			if ji.NumCols != nil {
				cols = *ji.NumCols
			}
			item = NewTableItem(ref, rows, cols)
		case "picture":
			mimeType := ""
			if ji.MimeType != nil {
				mimeType = *ji.MimeType
			}
			pictureItem := NewPictureItem(ref, mimeType)
			if len(ji.ImageData) > 0 {
				pictureItem = pictureItem.WithImageData(ji.ImageData)
			}
			item = pictureItem
		case "group":
			item = NewGroupItem(ref, label)
		case "node":
			item = NewNodeItem(ref, label)
		default:
			return fmt.Errorf("unknown item type: %s", ji.Type)
		}

		// Set parent
		if ji.Parent != nil {
			parentRef := Ref(*ji.Parent)
			switch v := item.(type) {
			case TextItem:
				v.DocItem = v.WithParent(parentRef)
				item = v
			case DocItem:
				item = v.WithParent(parentRef)
			case TableItem:
				v.DocItem = v.WithParent(parentRef)
				item = v
			case PictureItem:
				v.DocItem = v.WithParent(parentRef)
				item = v
			case GroupItem:
				v.NodeItem = v.WithParent(parentRef)
				item = v
			case NodeItem:
				item = v.WithParent(parentRef)
			}
		}

		// Set children
		if len(ji.Children) > 0 {
			childRefs := make([]Ref, len(ji.Children))
			for i, childStr := range ji.Children {
				childRefs[i] = Ref(childStr)
			}
			switch v := item.(type) {
			case TextItem:
				v.DocItem = v.WithChildren(childRefs)
				item = v
			case DocItem:
				item = v.WithChildren(childRefs)
			case TableItem:
				v.DocItem = v.WithChildren(childRefs)
				item = v
			case PictureItem:
				v.DocItem = v.WithChildren(childRefs)
				item = v
			case GroupItem:
				v.NodeItem = v.WithChildren(childRefs)
				item = v
			case NodeItem:
				item = v.WithChildren(childRefs)
			}
		}

		// Set provenance
		if len(ji.Provenance) > 0 {
			for _, prov := range ji.Provenance {
				switch v := item.(type) {
				case TextItem:
					v.DocItem = v.WithProvenance(prov)
					item = v
				case DocItem:
					item = v.WithProvenance(prov)
				case TableItem:
					v.DocItem = v.WithProvenance(prov)
					item = v
				case PictureItem:
					v.DocItem = v.WithProvenance(prov)
					item = v
				case GroupItem:
					v.NodeItem = v.WithProvenance(prov)
					item = v
				case NodeItem:
					item = v.WithProvenance(prov)
				}
			}
		}

		// Set metadata
		if ji.Metadata != nil {
			for key, value := range ji.Metadata {
				switch v := item.(type) {
				case TextItem:
					v.DocItem = v.DocItem.WithMetadata(key, value)
					item = v
				case DocItem:
					item = v.WithMetadata(key, value)
				case TableItem:
					v.DocItem = v.DocItem.WithMetadata(key, value)
					item = v
				case PictureItem:
					v.DocItem = v.DocItem.WithMetadata(key, value)
					item = v
				case GroupItem:
					v.NodeItem = v.NodeItem.WithMetadata(key, value)
					item = v
				case NodeItem:
					item = v.WithMetadata(key, value)
				}
			}
		}

		doc = doc.WithItem(item)
	}

	// Set body reference
	if jd.Body != nil {
		bodyRef := Ref(*jd.Body)
		doc = doc.WithBody(bodyRef)
	}

	*d = doc
	return nil
}

// ToJSON serializes the document to JSON bytes.
func ToJSON(doc DoclingDocument) ([]byte, error) {
	return json.Marshal(doc)
}

// ToJSONIndent serializes the document to indented JSON bytes.
func ToJSONIndent(doc DoclingDocument, prefix, indent string) ([]byte, error) {
	return json.MarshalIndent(doc, prefix, indent)
}

// FromJSON deserializes a document from JSON bytes.
func FromJSON(data []byte) (DoclingDocument, error) {
	var doc DoclingDocument
	if err := json.Unmarshal(data, &doc); err != nil {
		return DoclingDocument{}, err
	}
	return doc, nil
}
