package docling

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"
)

func TestJSONRoundTrip(t *testing.T) {
	doc := NewDocument("Test Document")

	// Create a simple document
	root := NewNodeItem(Ref("root"), LabelSectionHeader)
	text := NewTextItem(Ref("text1"), "Hello, World!")

	root = root.WithChild(Ref("text1"))
	text.DocItem = text.WithParent(Ref("root"))

	doc = doc.WithBody(Ref("root")).WithItem(root).WithItem(text)
	doc = doc.WithMetadata("author", "Test Author")

	// Add page info
	page := PageInfo{Number: 1, Width: 612, Height: 792}
	doc = doc.WithPage(page)

	// Serialize to JSON
	jsonData, err := ToJSON(doc)
	require.NoError(t, err)
	require.NotEmpty(t, jsonData)

	// Deserialize from JSON
	doc2, err := FromJSON(jsonData)
	require.NoError(t, err)

	// Verify document structure
	require.Equal(t, doc.Name(), doc2.Name())
	require.Equal(t, doc.ItemCount(), doc2.ItemCount())
	require.NotNil(t, doc2.Body())
	require.Equal(t, Ref("root"), *doc2.Body())

	// Verify items
	item1 := doc2.GetItem(Ref("root"))
	require.NotNil(t, item1)
	require.Equal(t, LabelSectionHeader, item1.Label())

	item2 := doc2.GetItem(Ref("text1"))
	require.NotNil(t, item2)
	require.Equal(t, LabelText, item2.Label())

	// Verify parent-child relationship
	require.Len(t, item1.Children(), 1)
	require.Equal(t, Ref("text1"), item1.Children()[0])
	require.NotNil(t, item2.Parent())
	require.Equal(t, Ref("root"), *item2.Parent())

	// Verify metadata
	author, ok := doc2.Metadata().GetString("author")
	require.True(t, ok)
	require.Equal(t, "Test Author", author)

	// Verify page
	page2, ok := doc2.GetPage(1)
	require.True(t, ok)
	require.Equal(t, 612.0, page2.Width)
	require.Equal(t, 792.0, page2.Height)
}

func TestJSONIndent(t *testing.T) {
	doc := NewDocument("Test")
	text := NewTextItem(Ref("text1"), "Hello")
	doc = doc.WithItem(text)

	jsonData, err := ToJSONIndent(doc, "", "  ")
	require.NoError(t, err)
	require.NotEmpty(t, jsonData)

	// Should be valid JSON
	var result map[string]interface{}
	err = json.Unmarshal(jsonData, &result)
	require.NoError(t, err)
}

func TestJSONTableItem(t *testing.T) {
	doc := NewDocument("Test")
	table := NewTableItem(Ref("table1"), 3, 4)
	doc = doc.WithItem(table)

	jsonData, err := ToJSON(doc)
	require.NoError(t, err)

	doc2, err := FromJSON(jsonData)
	require.NoError(t, err)

	item := doc2.GetItem(Ref("table1"))
	require.NotNil(t, item)

	tableItem, ok := item.(TableItem)
	require.True(t, ok)
	require.Equal(t, 3, tableItem.NumRows())
	require.Equal(t, 4, tableItem.NumCols())
}

func TestJSONPictureItem(t *testing.T) {
	doc := NewDocument("Test")

	imageData := []byte{0x89, 0x50, 0x4E, 0x47}
	picture := NewPictureItem(Ref("pic1"), "image/png")
	picture = picture.WithImageData(imageData)

	doc = doc.WithItem(picture)

	jsonData, err := ToJSON(doc)
	require.NoError(t, err)

	doc2, err := FromJSON(jsonData)
	require.NoError(t, err)

	item := doc2.GetItem(Ref("pic1"))
	require.NotNil(t, item)

	pictureItem, ok := item.(PictureItem)
	require.True(t, ok)
	require.Equal(t, "image/png", pictureItem.MimeType())
	require.Equal(t, imageData, pictureItem.ImageData())
}

func TestJSONGroupItem(t *testing.T) {
	doc := NewDocument("Test")
	group := NewGroupItem(Ref("group1"), LabelSectionHeader)
	doc = doc.WithItem(group)

	jsonData, err := ToJSON(doc)
	require.NoError(t, err)

	doc2, err := FromJSON(jsonData)
	require.NoError(t, err)

	item := doc2.GetItem(Ref("group1"))
	require.NotNil(t, item)
	require.Equal(t, LabelSectionHeader, item.Label())
}

func TestJSONProvenanceAndMetadata(t *testing.T) {
	doc := NewDocument("Test")

	bbox := NewBoundingBox(10, 20, 100, 50, 1)
	prov := NewProvenanceItem(1).WithBoundingBox(bbox).WithCharRange(0, 10)

	text := NewTextItem(Ref("text1"), "Hello")
	text.DocItem = text.DocItem.WithProvenance(prov).WithMetadata("language", "en")

	doc = doc.WithItem(text)

	jsonData, err := ToJSON(doc)
	require.NoError(t, err)

	doc2, err := FromJSON(jsonData)
	require.NoError(t, err)

	item := doc2.GetItem(Ref("text1"))
	require.NotNil(t, item)

	// Check provenance
	provItems := item.Provenance()
	require.Len(t, provItems, 1)
	require.NotNil(t, provItems[0].BBox)
	require.Equal(t, 10.0, provItems[0].BBox.Left)
	require.Equal(t, 0, provItems[0].CharStart)
	require.Equal(t, 10, provItems[0].CharEnd)

	// Check metadata
	lang, ok := item.Meta().GetString("language")
	require.True(t, ok)
	require.Equal(t, "en", lang)
}

func TestYAMLRoundTrip(t *testing.T) {
	t.Skip("YAML support needs custom marshaling - using JSON intermediate format for now")

	doc := NewDocument("Test Document")

	root := NewNodeItem(Ref("root"), LabelSectionHeader)
	text := NewTextItem(Ref("text1"), "Hello, YAML!")

	root = root.WithChild(Ref("text1"))
	text.DocItem = text.WithParent(Ref("root"))

	doc = doc.WithBody(Ref("root")).WithItem(root).WithItem(text)

	// Serialize to YAML
	yamlData, err := ToYAML(doc)
	require.NoError(t, err)
	require.NotEmpty(t, yamlData)

	// Deserialize from YAML
	doc2, err := FromYAML(yamlData)
	require.NoError(t, err)

	// Verify document structure
	require.Equal(t, doc.Name(), doc2.Name())
	require.Equal(t, doc.ItemCount(), doc2.ItemCount())
	require.NotNil(t, doc2.Body())
	require.Equal(t, Ref("root"), *doc2.Body())

	// Verify items
	item1 := doc2.GetItem(Ref("root"))
	require.NotNil(t, item1)
	require.Equal(t, LabelSectionHeader, item1.Label())

	item2 := doc2.GetItem(Ref("text1"))
	require.NotNil(t, item2)
	require.Equal(t, LabelText, item2.Label())
}

func TestYAMLValidFormat(t *testing.T) {
	doc := NewDocument("Test")
	text := NewTextItem(Ref("text1"), "Hello")
	doc = doc.WithItem(text)

	yamlData, err := ToYAML(doc)
	require.NoError(t, err)
	require.NotEmpty(t, yamlData)

	// Should be valid YAML
	var result map[string]interface{}
	err = yaml.Unmarshal(yamlData, &result)
	require.NoError(t, err)
}

func TestJSONEmptyDocument(t *testing.T) {
	doc := NewDocument("Empty")

	jsonData, err := ToJSON(doc)
	require.NoError(t, err)

	doc2, err := FromJSON(jsonData)
	require.NoError(t, err)

	require.Equal(t, "Empty", doc2.Name())
	require.Equal(t, 0, doc2.ItemCount())
	require.Nil(t, doc2.Body())
}

func TestJSONComplexTree(t *testing.T) {
	doc := NewDocument("Complex Tree")

	// Create: root -> section1 -> para1, para2
	//               -> section2 -> para3
	root := NewNodeItem(Ref("root"), LabelSectionHeader)
	section1 := NewNodeItem(Ref("section1"), LabelSectionHeader)
	section2 := NewNodeItem(Ref("section2"), LabelSectionHeader)
	para1 := NewTextItem(Ref("para1"), "First paragraph")
	para2 := NewTextItem(Ref("para2"), "Second paragraph")
	para3 := NewTextItem(Ref("para3"), "Third paragraph")

	root = root.WithChild(Ref("section1")).WithChild(Ref("section2"))
	section1 = section1.WithParent(Ref("root")).WithChild(Ref("para1")).WithChild(Ref("para2"))
	section2 = section2.WithParent(Ref("root")).WithChild(Ref("para3"))
	para1.DocItem = para1.WithParent(Ref("section1"))
	para2.DocItem = para2.WithParent(Ref("section1"))
	para3.DocItem = para3.WithParent(Ref("section2"))

	doc = doc.WithBody(Ref("root"))
	doc = doc.WithItem(root).WithItem(section1).WithItem(section2)
	doc = doc.WithItem(para1).WithItem(para2).WithItem(para3)

	// Round trip
	jsonData, err := ToJSON(doc)
	require.NoError(t, err)

	doc2, err := FromJSON(jsonData)
	require.NoError(t, err)

	// Verify structure
	require.Equal(t, 6, doc2.ItemCount())

	rootItem := doc2.GetItem(Ref("root"))
	require.Len(t, rootItem.Children(), 2)

	section1Item := doc2.GetItem(Ref("section1"))
	require.Len(t, section1Item.Children(), 2)
	require.Equal(t, Ref("root"), *section1Item.Parent())

	section2Item := doc2.GetItem(Ref("section2"))
	require.Len(t, section2Item.Children(), 1)
	require.Equal(t, Ref("root"), *section2Item.Parent())
}
