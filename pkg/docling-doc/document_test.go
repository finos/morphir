package docling

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewDocument(t *testing.T) {
	doc := NewDocument("Test Document")

	require.Equal(t, "Test Document", doc.Name())
	require.Nil(t, doc.Body())
	require.Equal(t, 0, doc.ItemCount())
	require.Empty(t, doc.Pages())
}

func TestDocumentImmutability(t *testing.T) {
	doc := NewDocument("Test")
	item := NewTextItem(Ref("text1"), "Hello")

	// WithItem should return new document
	doc2 := doc.WithItem(item)
	require.Equal(t, 0, doc.ItemCount())
	require.Equal(t, 1, doc2.ItemCount())
	require.True(t, doc2.HasItem(Ref("text1")))

	// WithName should return new document
	doc3 := doc2.WithName("New Name")
	require.Equal(t, "Test", doc2.Name())
	require.Equal(t, "New Name", doc3.Name())

	// WithBody should return new document
	doc4 := doc2.WithBody(Ref("text1"))
	require.Nil(t, doc2.Body())
	require.NotNil(t, doc4.Body())
	require.Equal(t, Ref("text1"), *doc4.Body())
}

func TestDocumentWithItem(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")

	doc = doc.WithItem(text1)
	doc = doc.WithItem(text2)

	require.Equal(t, 2, doc.ItemCount())
	require.True(t, doc.HasItem(Ref("text1")))
	require.True(t, doc.HasItem(Ref("text2")))

	item1 := doc.GetItem(Ref("text1"))
	require.NotNil(t, item1)
	require.Equal(t, Ref("text1"), item1.SelfRef())
}

func TestDocumentWithoutItem(t *testing.T) {
	doc := NewDocument("Test")
	text := NewTextItem(Ref("text1"), "Hello")

	doc = doc.WithItem(text)
	require.Equal(t, 1, doc.ItemCount())

	doc2 := doc.WithoutItem(Ref("text1"))
	require.Equal(t, 1, doc.ItemCount())
	require.Equal(t, 0, doc2.ItemCount())
	require.False(t, doc2.HasItem(Ref("text1")))

	// Removing non-existent item should return same document
	doc3 := doc2.WithoutItem(Ref("nonexistent"))
	require.Equal(t, 0, doc3.ItemCount())
}

func TestDocumentPages(t *testing.T) {
	doc := NewDocument("Test")

	page1 := PageInfo{Number: 1, Width: 612, Height: 792}
	page2 := PageInfo{Number: 2, Width: 612, Height: 792}

	doc = doc.WithPage(page1).WithPage(page2)

	require.Len(t, doc.Pages(), 2)

	p1, ok := doc.GetPage(1)
	require.True(t, ok)
	require.Equal(t, 612.0, p1.Width)

	p2, ok := doc.GetPage(2)
	require.True(t, ok)
	require.Equal(t, 792.0, p2.Height)

	_, ok = doc.GetPage(3)
	require.False(t, ok)
}

func TestDocumentMetadata(t *testing.T) {
	doc := NewDocument("Test")

	doc = doc.WithMetadata("author", "John Doe")
	doc = doc.WithMetadata("version", 1)

	author, ok := doc.Metadata().GetString("author")
	require.True(t, ok)
	require.Equal(t, "John Doe", author)

	version, ok := doc.Metadata().GetInt("version")
	require.True(t, ok)
	require.Equal(t, 1, version)
}

func TestDocumentGetChildren(t *testing.T) {
	doc := NewDocument("Test")

	parent := NewNodeItem(Ref("parent"), LabelSectionHeader)
	child1 := NewTextItem(Ref("child1"), "First")
	child2 := NewTextItem(Ref("child2"), "Second")

	// Set up parent-child relationships
	parent = parent.WithChild(Ref("child1")).WithChild(Ref("child2"))
	child1.DocItem = child1.WithParent(Ref("parent"))
	child2.DocItem = child2.WithParent(Ref("parent"))

	doc = doc.WithItem(parent).WithItem(child1).WithItem(child2)

	children := doc.GetChildren(Ref("parent"))
	require.Len(t, children, 2)
	require.Equal(t, Ref("child1"), children[0].SelfRef())
	require.Equal(t, Ref("child2"), children[1].SelfRef())

	// Non-existent item should return empty slice
	emptyChildren := doc.GetChildren(Ref("nonexistent"))
	require.Empty(t, emptyChildren)
}

func TestDocumentGetParent(t *testing.T) {
	doc := NewDocument("Test")

	parent := NewNodeItem(Ref("parent"), LabelSectionHeader)
	child := NewTextItem(Ref("child"), "Text")

	parent = parent.WithChild(Ref("child"))
	child.DocItem = child.WithParent(Ref("parent"))

	doc = doc.WithItem(parent).WithItem(child)

	parentItem := doc.GetParent(Ref("child"))
	require.NotNil(t, parentItem)
	require.Equal(t, Ref("parent"), parentItem.SelfRef())

	// Item with no parent
	noParent := doc.GetParent(Ref("parent"))
	require.Nil(t, noParent)
}

func TestDocumentGetSiblings(t *testing.T) {
	doc := NewDocument("Test")

	parent := NewNodeItem(Ref("parent"), LabelSectionHeader)
	child1 := NewTextItem(Ref("child1"), "First")
	child2 := NewTextItem(Ref("child2"), "Second")
	child3 := NewTextItem(Ref("child3"), "Third")

	parent = parent.WithChild(Ref("child1")).WithChild(Ref("child2")).WithChild(Ref("child3"))
	child1.DocItem = child1.WithParent(Ref("parent"))
	child2.DocItem = child2.WithParent(Ref("parent"))
	child3.DocItem = child3.WithParent(Ref("parent"))

	doc = doc.WithItem(parent).WithItem(child1).WithItem(child2).WithItem(child3)

	siblings := doc.GetSiblings(Ref("child2"))
	require.Len(t, siblings, 2)

	// Check that child2 is not in siblings
	for _, sibling := range siblings {
		require.NotEqual(t, Ref("child2"), sibling.SelfRef())
	}
}

func TestDocumentGetDescendants(t *testing.T) {
	doc := NewDocument("Test")

	// Create a tree: root -> section1 -> para1, para2
	root := NewNodeItem(Ref("root"), LabelSectionHeader)
	section := NewNodeItem(Ref("section1"), LabelSectionHeader)
	para1 := NewTextItem(Ref("para1"), "First paragraph")
	para2 := NewTextItem(Ref("para2"), "Second paragraph")

	root = root.WithChild(Ref("section1"))
	section = section.WithParent(Ref("root")).WithChild(Ref("para1")).WithChild(Ref("para2"))
	para1.DocItem = para1.WithParent(Ref("section1"))
	para2.DocItem = para2.WithParent(Ref("section1"))

	doc = doc.WithItem(root).WithItem(section).WithItem(para1).WithItem(para2)

	descendants := doc.GetDescendants(Ref("root"))
	require.Len(t, descendants, 3) // section1, para1, para2
}

func TestDocumentGetAncestors(t *testing.T) {
	doc := NewDocument("Test")

	// Create a tree: root -> section1 -> para1
	root := NewNodeItem(Ref("root"), LabelSectionHeader)
	section := NewNodeItem(Ref("section1"), LabelSectionHeader)
	para := NewTextItem(Ref("para1"), "Paragraph")

	root = root.WithChild(Ref("section1"))
	section = section.WithParent(Ref("root")).WithChild(Ref("para1"))
	para.DocItem = para.WithParent(Ref("section1"))

	doc = doc.WithItem(root).WithItem(section).WithItem(para)

	ancestors := doc.GetAncestors(Ref("para1"))
	require.Len(t, ancestors, 2) // section1, root
	require.Equal(t, Ref("section1"), ancestors[0].SelfRef())
	require.Equal(t, Ref("root"), ancestors[1].SelfRef())

	// Root has no ancestors
	rootAncestors := doc.GetAncestors(Ref("root"))
	require.Empty(t, rootAncestors)
}

func TestDocumentIsAncestorOf(t *testing.T) {
	doc := NewDocument("Test")

	// Create a tree: root -> section1 -> para1
	root := NewNodeItem(Ref("root"), LabelSectionHeader)
	section := NewNodeItem(Ref("section1"), LabelSectionHeader)
	para := NewTextItem(Ref("para1"), "Paragraph")

	root = root.WithChild(Ref("section1"))
	section = section.WithParent(Ref("root")).WithChild(Ref("para1"))
	para.DocItem = para.WithParent(Ref("section1"))

	doc = doc.WithItem(root).WithItem(section).WithItem(para)

	require.True(t, doc.IsAncestorOf(Ref("root"), Ref("para1")))
	require.True(t, doc.IsAncestorOf(Ref("section1"), Ref("para1")))
	require.False(t, doc.IsAncestorOf(Ref("para1"), Ref("root")))
	require.False(t, doc.IsAncestorOf(Ref("section1"), Ref("root")))
}

func TestDocumentItems(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")

	doc = doc.WithItem(text1).WithItem(text2)

	items := doc.Items()
	require.Len(t, items, 2)

	// Mutating returned map shouldn't affect document
	delete(items, Ref("text1"))
	require.Equal(t, 2, doc.ItemCount())
}
