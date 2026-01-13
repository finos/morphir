package docling

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestWalk(t *testing.T) {
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

	var visited []Ref
	err := Walk(doc, Ref("root"), func(item Item) error {
		visited = append(visited, item.SelfRef())
		return nil
	})

	require.NoError(t, err)
	require.Len(t, visited, 4) // root, section1, para1, para2
	require.Equal(t, Ref("root"), visited[0])
	require.Equal(t, Ref("section1"), visited[1])
}

func TestWalkBody(t *testing.T) {
	doc := NewDocument("Test")

	root := NewNodeItem(Ref("root"), LabelSectionHeader)
	child := NewTextItem(Ref("child1"), "Text")

	root = root.WithChild(Ref("child1"))
	child.DocItem = child.WithParent(Ref("root"))

	doc = doc.WithBody(Ref("root")).WithItem(root).WithItem(child)

	var visited []Ref
	err := WalkBody(doc, func(item Item) error {
		visited = append(visited, item.SelfRef())
		return nil
	})

	require.NoError(t, err)
	require.Len(t, visited, 2)
	require.Equal(t, Ref("root"), visited[0])
	require.Equal(t, Ref("child1"), visited[1])
}

func TestWalkBodyEmpty(t *testing.T) {
	doc := NewDocument("Test")

	// Document with no body
	err := WalkBody(doc, func(item Item) error {
		t.Fatal("Should not be called")
		return nil
	})

	require.NoError(t, err)
}

func TestWalkAll(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")

	doc = doc.WithItem(text1).WithItem(text2)

	var visited []Ref
	err := WalkAll(doc, func(item Item) error {
		visited = append(visited, item.SelfRef())
		return nil
	})

	require.NoError(t, err)
	require.Len(t, visited, 2)
}

func TestFilter(t *testing.T) {
	doc := NewDocument("Test")

	text := NewTextItem(Ref("text1"), "Text")
	table := NewTableItem(Ref("table1"), 2, 2)
	picture := NewPictureItem(Ref("pic1"), "image/png")

	doc = doc.WithItem(text).WithItem(table).WithItem(picture)

	// Filter only text items
	filtered := Filter(doc, func(item Item) bool {
		return item.Label() == LabelText
	})

	require.Equal(t, 1, filtered.ItemCount())
	require.True(t, filtered.HasItem(Ref("text1")))
	require.False(t, filtered.HasItem(Ref("table1")))
	require.False(t, filtered.HasItem(Ref("pic1")))
}

func TestFilterByLabel(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")
	table := NewTableItem(Ref("table1"), 2, 2)

	doc = doc.WithItem(text1).WithItem(text2).WithItem(table)

	filtered := FilterByLabel(doc, LabelText)

	require.Equal(t, 2, filtered.ItemCount())
	require.True(t, filtered.HasItem(Ref("text1")))
	require.True(t, filtered.HasItem(Ref("text2")))
	require.False(t, filtered.HasItem(Ref("table1")))
}

func TestMap(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")

	doc = doc.WithItem(text1).WithItem(text2)

	// Add metadata to all items
	mapped := Map(doc, func(item Item) Item {
		switch v := item.(type) {
		case TextItem:
			v.DocItem = v.WithMetadata("processed", true)
			return v
		default:
			return item
		}
	})

	item1 := mapped.GetItem(Ref("text1"))
	_, ok := item1.Meta().Get("processed")
	require.True(t, ok)
}

func TestFold(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")
	text3 := NewTextItem(Ref("text3"), "Third")

	doc = doc.WithItem(text1).WithItem(text2).WithItem(text3)

	// Count total items
	count := Fold(doc, 0, func(acc int, item Item) int {
		return acc + 1
	})

	require.Equal(t, 3, count)
}

func TestCollect(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")
	table := NewTableItem(Ref("table1"), 2, 2)

	doc = doc.WithItem(text1).WithItem(text2).WithItem(table)

	texts := Collect(doc, func(item Item) bool {
		return item.Label() == LabelText
	})

	require.Len(t, texts, 2)
}

func TestCollectByLabel(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	table1 := NewTableItem(Ref("table1"), 2, 2)
	table2 := NewTableItem(Ref("table2"), 3, 3)

	doc = doc.WithItem(text1).WithItem(table1).WithItem(table2)

	tables := CollectByLabel(doc, LabelTable)

	require.Len(t, tables, 2)
}

func TestFind(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")

	doc = doc.WithItem(text1).WithItem(text2)

	found := Find(doc, func(item Item) bool {
		return item.SelfRef() == Ref("text2")
	})

	require.NotNil(t, found)
	require.Equal(t, Ref("text2"), found.SelfRef())

	notFound := Find(doc, func(item Item) bool {
		return item.SelfRef() == Ref("nonexistent")
	})

	require.Nil(t, notFound)
}

func TestFindByLabel(t *testing.T) {
	doc := NewDocument("Test")

	text := NewTextItem(Ref("text1"), "Text")
	table := NewTableItem(Ref("table1"), 2, 2)

	doc = doc.WithItem(text).WithItem(table)

	found := FindByLabel(doc, LabelTable)
	require.NotNil(t, found)
	require.Equal(t, LabelTable, found.Label())
}

func TestAny(t *testing.T) {
	doc := NewDocument("Test")

	text := NewTextItem(Ref("text1"), "Text")
	table := NewTableItem(Ref("table1"), 2, 2)

	doc = doc.WithItem(text).WithItem(table)

	hasTable := Any(doc, func(item Item) bool {
		return item.Label() == LabelTable
	})

	require.True(t, hasTable)

	hasPicture := Any(doc, func(item Item) bool {
		return item.Label() == LabelPicture
	})

	require.False(t, hasPicture)
}

func TestAll(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")

	doc = doc.WithItem(text1).WithItem(text2)

	allText := All(doc, func(item Item) bool {
		return item.Label() == LabelText
	})

	require.True(t, allText)

	// Add a table
	table := NewTableItem(Ref("table1"), 2, 2)
	doc = doc.WithItem(table)

	allText = All(doc, func(item Item) bool {
		return item.Label() == LabelText
	})

	require.False(t, allText)
}

func TestCount(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")
	table := NewTableItem(Ref("table1"), 2, 2)

	doc = doc.WithItem(text1).WithItem(text2).WithItem(table)

	textCount := Count(doc, func(item Item) bool {
		return item.Label() == LabelText
	})

	require.Equal(t, 2, textCount)
}

func TestCountByLabel(t *testing.T) {
	doc := NewDocument("Test")

	text1 := NewTextItem(Ref("text1"), "First")
	text2 := NewTextItem(Ref("text2"), "Second")
	text3 := NewTextItem(Ref("text3"), "Third")
	table := NewTableItem(Ref("table1"), 2, 2)

	doc = doc.WithItem(text1).WithItem(text2).WithItem(text3).WithItem(table)

	textCount := CountByLabel(doc, LabelText)
	require.Equal(t, 3, textCount)

	tableCount := CountByLabel(doc, LabelTable)
	require.Equal(t, 1, tableCount)
}

func TestIterateTree(t *testing.T) {
	doc := NewDocument("Test")

	root := NewNodeItem(Ref("root"), LabelSectionHeader)
	child1 := NewTextItem(Ref("child1"), "First")
	child2 := NewTextItem(Ref("child2"), "Second")

	root = root.WithChild(Ref("child1")).WithChild(Ref("child2"))
	child1.DocItem = child1.WithParent(Ref("root"))
	child2.DocItem = child2.WithParent(Ref("root"))

	doc = doc.WithItem(root).WithItem(child1).WithItem(child2)

	var visited []Ref
	for item := range IterateTree(doc, Ref("root")) {
		visited = append(visited, item.SelfRef())
	}

	require.Len(t, visited, 3) // root, child1, child2
	require.Equal(t, Ref("root"), visited[0])
}

func TestIterateBody(t *testing.T) {
	doc := NewDocument("Test")

	root := NewNodeItem(Ref("root"), LabelSectionHeader)
	child := NewTextItem(Ref("child1"), "Text")

	root = root.WithChild(Ref("child1"))
	child.DocItem = child.WithParent(Ref("root"))

	doc = doc.WithBody(Ref("root")).WithItem(root).WithItem(child)

	var visited []Ref
	for item := range IterateBody(doc) {
		visited = append(visited, item.SelfRef())
	}

	require.Len(t, visited, 2)
}

func TestIterateBodyEmpty(t *testing.T) {
	doc := NewDocument("Test")

	// Document with no body
	var visited []Ref
	for item := range IterateBody(doc) {
		visited = append(visited, item.SelfRef())
	}

	require.Empty(t, visited)
}
