package docling

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNodeItemImmutability(t *testing.T) {
	node := NewNodeItem(Ref("node1"), LabelText)

	require.Equal(t, Ref("node1"), node.SelfRef())
	require.Nil(t, node.Parent())
	require.Empty(t, node.Children())
	require.Equal(t, LabelText, node.Label())

	// WithParent should return new instance
	node2 := node.WithParent(Ref("parent1"))
	require.Nil(t, node.Parent())
	require.NotNil(t, node2.Parent())
	require.Equal(t, Ref("parent1"), *node2.Parent())

	// WithChild should return new instance
	node3 := node2.WithChild(Ref("child1"))
	require.Empty(t, node2.Children())
	require.Len(t, node3.Children(), 1)
	require.Equal(t, Ref("child1"), node3.Children()[0])

	// WithChildren should return new instance
	children := []Ref{Ref("child1"), Ref("child2")}
	node4 := node.WithChildren(children)
	require.Empty(t, node.Children())
	require.Len(t, node4.Children(), 2)

	// Mutating original slice shouldn't affect node
	children[0] = Ref("mutated")
	require.Equal(t, Ref("child1"), node4.Children()[0])

	// Mutating returned slice shouldn't affect node
	returnedChildren := node4.Children()
	returnedChildren[0] = Ref("mutated2")
	require.Equal(t, Ref("child1"), node4.Children()[0])
}

func TestNodeItemWithProvenance(t *testing.T) {
	node := NewNodeItem(Ref("node1"), LabelText)
	prov := NewProvenanceItem(1)

	node2 := node.WithProvenance(prov)
	require.Empty(t, node.Provenance())
	require.Len(t, node2.Provenance(), 1)
}

func TestNodeItemWithMetadata(t *testing.T) {
	node := NewNodeItem(Ref("node1"), LabelText)

	node2 := node.WithMetadata("key1", "value1")
	require.Empty(t, node.Meta())
	require.Len(t, node2.Meta(), 1)

	val, ok := node2.Meta().GetString("key1")
	require.True(t, ok)
	require.Equal(t, "value1", val)
}

func TestDocItemText(t *testing.T) {
	item := NewDocItem(Ref("item1"), LabelParagraph, "Hello, World!")

	require.Equal(t, "Hello, World!", item.Text())

	item2 := item.WithText("New text")
	require.Equal(t, "Hello, World!", item.Text())
	require.Equal(t, "New text", item2.Text())
}

func TestDocItemInheritsNodeMethods(t *testing.T) {
	item := NewDocItem(Ref("item1"), LabelParagraph, "Text")

	// Test WithParent
	item2 := item.WithParent(Ref("parent1"))
	require.Nil(t, item.Parent())
	require.NotNil(t, item2.Parent())

	// Test WithChild
	item3 := item2.WithChild(Ref("child1"))
	require.Empty(t, item2.Children())
	require.Len(t, item3.Children(), 1)

	// Test WithProvenance
	prov := NewProvenanceItem(1)
	item4 := item.WithProvenance(prov)
	require.Empty(t, item.Provenance())
	require.Len(t, item4.Provenance(), 1)

	// Test WithMetadata
	item5 := item.WithMetadata("key", "value")
	require.Empty(t, item.Meta())
	require.Len(t, item5.Meta(), 1)
}

func TestTextItem(t *testing.T) {
	textItem := NewTextItem(Ref("text1"), "Sample text")

	// TextItem embeds DocItem
	require.Equal(t, "Sample text", textItem.Text())
	require.Equal(t, LabelText, textItem.Label())
}

func TestTableItem(t *testing.T) {
	table := NewTableItem(Ref("table1"), 5, 3)

	require.Equal(t, 5, table.NumRows())
	require.Equal(t, 3, table.NumCols())
	require.Equal(t, LabelTable, table.Label())
}

func TestPictureItem(t *testing.T) {
	picture := NewPictureItem(Ref("pic1"), "image/png")

	require.Equal(t, "image/png", picture.MimeType())
	require.Empty(t, picture.ImageData())

	imageData := []byte{0x89, 0x50, 0x4E, 0x47}
	picture2 := picture.WithImageData(imageData)

	// Original should be unchanged
	require.Empty(t, picture.ImageData())
	require.Equal(t, imageData, picture2.ImageData())

	// Mutating input shouldn't affect item
	imageData[0] = 0xFF
	require.Equal(t, byte(0x89), picture2.ImageData()[0])

	// Mutating output shouldn't affect item
	output := picture2.ImageData()
	output[0] = 0xFF
	require.Equal(t, byte(0x89), picture2.ImageData()[0])
}

func TestGroupItem(t *testing.T) {
	group := NewGroupItem(Ref("group1"), LabelSectionHeader)

	// GroupItem embeds NodeItem
	require.Equal(t, LabelSectionHeader, group.Label())
	require.Equal(t, Ref("group1"), group.SelfRef())
}

func TestItemInterface(t *testing.T) {
	// All item types should implement the Item interface
	var items []Item

	items = append(items, NewNodeItem(Ref("node1"), LabelText))
	items = append(items, NewDocItem(Ref("doc1"), LabelParagraph, "text"))
	items = append(items, NewTextItem(Ref("text1"), "text"))
	items = append(items, NewTableItem(Ref("table1"), 2, 2))
	items = append(items, NewPictureItem(Ref("pic1"), "image/png"))
	items = append(items, NewGroupItem(Ref("group1"), LabelSectionHeader))

	// Verify all items implement the interface correctly
	for _, item := range items {
		require.NotNil(t, item.SelfRef())
		require.NotNil(t, item.Label())
		require.NotNil(t, item.Children())
		require.NotNil(t, item.Provenance())
		require.NotNil(t, item.Meta())
	}
}
