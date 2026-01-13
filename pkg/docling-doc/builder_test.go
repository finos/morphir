package docling

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewBuilder(t *testing.T) {
	b := NewBuilder("Test")

	require.NotNil(t, b)
	require.Equal(t, 0, b.ItemCount())
	require.Equal(t, 0, b.PageCount())
}

func TestBuilderFluentAPI(t *testing.T) {
	doc := NewBuilder("Report").
		AddTextItem(Ref("intro"), "Introduction").
		AddTextItem(Ref("body"), "Main content").
		WithMetadata("author", "Alice").
		WithMetadata("version", "1.0").
		Build()

	require.Equal(t, "Report", doc.Name())
	require.Equal(t, 2, doc.ItemCount())

	author, ok := doc.Metadata().GetString("author")
	require.True(t, ok)
	require.Equal(t, "Alice", author)

	version, ok := doc.Metadata().GetString("version")
	require.True(t, ok)
	require.Equal(t, "1.0", version)
}

func TestBuilderAddItems(t *testing.T) {
	b := NewBuilder("Test")

	b.AddTextItem(Ref("text1"), "Hello")
	b.AddTableItem(Ref("table1"), 3, 4)
	b.AddPictureItem(Ref("pic1"), "image/png")
	b.AddNodeItem(Ref("node1"), LabelSectionHeader)
	b.AddGroupItem(Ref("group1"), LabelList)

	require.Equal(t, 5, b.ItemCount())

	doc := b.Build()
	require.Equal(t, 5, doc.ItemCount())

	// Verify item types
	require.True(t, doc.HasItem(Ref("text1")))
	require.True(t, doc.HasItem(Ref("table1")))
	require.True(t, doc.HasItem(Ref("pic1")))
	require.True(t, doc.HasItem(Ref("node1")))
	require.True(t, doc.HasItem(Ref("group1")))
}

func TestBuilderRemoveItem(t *testing.T) {
	b := NewBuilder("Test").
		AddTextItem(Ref("text1"), "Hello").
		AddTextItem(Ref("text2"), "World")

	require.Equal(t, 2, b.ItemCount())

	b.RemoveItem(Ref("text1"))
	require.Equal(t, 1, b.ItemCount())

	doc := b.Build()
	require.False(t, doc.HasItem(Ref("text1")))
	require.True(t, doc.HasItem(Ref("text2")))
}

func TestBuilderWithBody(t *testing.T) {
	doc := NewBuilder("Test").
		AddGroupItem(Ref("root"), LabelSectionHeader).
		WithBody(Ref("root")).
		Build()

	require.NotNil(t, doc.Body())
	require.Equal(t, Ref("root"), *doc.Body())
}

func TestBuilderAddPages(t *testing.T) {
	b := NewBuilder("Test").
		AddPageSimple(1, 612, 792).
		AddPageSimple(2, 612, 792)

	require.Equal(t, 2, b.PageCount())

	doc := b.Build()
	pages := doc.Pages()
	require.Len(t, pages, 2)

	page1, ok := doc.GetPage(1)
	require.True(t, ok)
	require.Equal(t, 612.0, page1.Width)
	require.Equal(t, 792.0, page1.Height)
}

func TestBuilderReset(t *testing.T) {
	b := NewBuilder("First").
		AddTextItem(Ref("text1"), "Hello").
		WithMetadata("author", "Alice")

	require.Equal(t, 1, b.ItemCount())

	b.Reset("Second")

	require.Equal(t, "Second", b.name)
	require.Equal(t, 0, b.ItemCount())
	require.Empty(t, b.metadata)

	doc := b.AddTextItem(Ref("text2"), "World").Build()

	require.Equal(t, "Second", doc.Name())
	require.Equal(t, 1, doc.ItemCount())
	require.True(t, doc.HasItem(Ref("text2")))
	require.False(t, doc.HasItem(Ref("text1")))
}

func TestBuilderReuse(t *testing.T) {
	b := NewBuilder("Test")

	// Build first document
	doc1 := b.AddTextItem(Ref("text1"), "First").Build()
	require.Equal(t, 1, doc1.ItemCount())

	// Build second document (builder state is preserved)
	doc2 := b.AddTextItem(Ref("text2"), "Second").Build()
	require.Equal(t, 2, doc2.ItemCount())

	// First document is still unchanged
	require.Equal(t, 1, doc1.ItemCount())
}

func TestBuilderGetItem(t *testing.T) {
	b := NewBuilder("Test").
		AddTextItem(Ref("text1"), "Hello")

	item := b.GetItem(Ref("text1"))
	require.NotNil(t, item)
	require.Equal(t, Ref("text1"), item.SelfRef())

	// Non-existent item
	item = b.GetItem(Ref("nonexistent"))
	require.Nil(t, item)
}

func TestBuilderHasItem(t *testing.T) {
	b := NewBuilder("Test").
		AddTextItem(Ref("text1"), "Hello")

	require.True(t, b.HasItem(Ref("text1")))
	require.False(t, b.HasItem(Ref("nonexistent")))
}

func TestNewBuilderFrom(t *testing.T) {
	// Create an immutable document
	doc := NewDocument("Original").
		WithItem(NewTextItem(Ref("text1"), "Hello")).
		WithItem(NewTableItem(Ref("table1"), 2, 2)).
		WithMetadata("author", "Alice").
		WithBody(Ref("text1"))

	page := PageInfo{Number: 1, Width: 612, Height: 792}
	doc = doc.WithPage(page)

	// Create builder from document
	b := NewBuilderFrom(doc)

	require.Equal(t, "Original", b.name)
	require.Equal(t, 2, b.ItemCount())
	require.Equal(t, 1, b.PageCount())
	require.NotNil(t, b.body)
	require.Equal(t, Ref("text1"), *b.body)

	// Modify builder
	b.AddTextItem(Ref("text2"), "World").
		WithMetadata("version", "1.0")

	// Build new document
	doc2 := b.Build()

	// New document has modifications
	require.Equal(t, 3, doc2.ItemCount())
	version, ok := doc2.Metadata().GetString("version")
	require.True(t, ok)
	require.Equal(t, "1.0", version)

	// Original document is unchanged
	require.Equal(t, 2, doc.ItemCount())
	_, ok = doc.Metadata().GetString("version")
	require.False(t, ok)
}

func TestBuilderPictureWithData(t *testing.T) {
	imageData := []byte{0x89, 0x50, 0x4E, 0x47}

	doc := NewBuilder("Test").
		AddPictureItemWithData(Ref("pic1"), "image/png", imageData).
		Build()

	item := doc.GetItem(Ref("pic1"))
	require.NotNil(t, item)

	pic, ok := item.(PictureItem)
	require.True(t, ok)
	require.Equal(t, "image/png", pic.MimeType())
	require.Equal(t, imageData, pic.ImageData())
}

func TestBuilderComplexDocument(t *testing.T) {
	// Build a complex document with hierarchy
	root := NewGroupItem(Ref("root"), LabelSectionHeader)
	section1 := NewNodeItem(Ref("section1"), LabelSectionHeader).
		WithParent(Ref("root"))
	para1 := NewTextItem(Ref("para1"), "First paragraph")
	para1.DocItem = para1.WithParent(Ref("section1"))
	para2 := NewTextItem(Ref("para2"), "Second paragraph")
	para2.DocItem = para2.WithParent(Ref("section1"))

	root.NodeItem = root.WithChild(Ref("section1"))
	section1 = section1.WithChild(Ref("para1")).WithChild(Ref("para2"))

	doc := NewBuilder("Complex Document").
		AddItem(root).
		AddItem(section1).
		AddItem(para1).
		AddItem(para2).
		WithBody(Ref("root")).
		WithMetadata("author", "Bob").
		AddPageSimple(1, 612, 792).
		Build()

	require.Equal(t, 4, doc.ItemCount())
	require.NotNil(t, doc.Body())
	require.Equal(t, Ref("root"), *doc.Body())

	// Verify hierarchy
	rootItem := doc.GetItem(Ref("root"))
	require.Len(t, rootItem.Children(), 1)

	section1Item := doc.GetItem(Ref("section1"))
	require.Len(t, section1Item.Children(), 2)
}

func TestBuilderEfficiency(t *testing.T) {
	// This test demonstrates the efficiency gain
	// With immutable API: each WithItem creates a new map
	// With builder: single map is modified in place

	b := NewBuilder("Efficiency Test")

	// Add 100 items efficiently
	for i := 0; i < 100; i++ {
		b.AddTextItem(Ref("text"+string(rune(i))), "Content")
	}

	doc := b.Build()
	require.Equal(t, 100, doc.ItemCount())
}

func BenchmarkBuilderVsImmutable(b *testing.B) {
	b.Run("Builder", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			builder := NewBuilder("Test")
			for j := 0; j < 50; j++ {
				builder.AddTextItem(Ref("text"+string(rune(j))), "Content")
			}
			_ = builder.Build()
		}
	})

	b.Run("Immutable", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			doc := NewDocument("Test")
			for j := 0; j < 50; j++ {
				doc = doc.WithItem(NewTextItem(Ref("text"+string(rune(j))), "Content"))
			}
		}
	})
}
