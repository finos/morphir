package vfs

import (
	"io"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestMemFileCopiesData(t *testing.T) {
	orig := []byte("hello")
	file := NewMemFile(MustVPath("/file.txt"), Meta{}, Origin{}, orig)

	orig[0] = 'H'
	data, err := file.Bytes()
	require.NoError(t, err)
	require.Equal(t, []byte("hello"), data)

	data[1] = 'A'
	data2, err := file.Bytes()
	require.NoError(t, err)
	require.Equal(t, []byte("hello"), data2)
}

func TestMemFileStream(t *testing.T) {
	file := NewMemFile(MustVPath("/file.txt"), Meta{}, Origin{}, []byte("stream"))
	reader, err := file.Stream()
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, reader.Close())
	})

	buf, err := io.ReadAll(reader)
	require.NoError(t, err)
	require.Equal(t, []byte("stream"), buf)
}

func TestMemFolderCopiesChildren(t *testing.T) {
	child := NewMemFile(MustVPath("/child.txt"), Meta{}, Origin{}, []byte("ok"))
	children := []Entry{child}
	folder := NewMemFolder(MustVPath("/"), Meta{}, Origin{}, children)

	children[0] = NewMemFile(MustVPath("/other.txt"), Meta{}, Origin{}, []byte("nope"))

	got, err := folder.Children()
	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, MustVPath("/child.txt"), got[0].Path())
}

func TestMemFolderCopiesMeta(t *testing.T) {
	meta := Meta{
		Dynamic: map[string]any{"key": "value"},
		Typed:   map[string]any{"morphir": 1},
	}
	folder := NewMemFolder(MustVPath("/"), meta, Origin{}, nil)

	meta.Dynamic["key"] = "changed"
	meta.Typed["morphir"] = 2

	got := folder.Meta()
	require.Equal(t, "value", got.Dynamic["key"])
	require.Equal(t, 1, got.Typed["morphir"])

	got.Dynamic["key"] = "mutated"
	got2 := folder.Meta()
	require.Equal(t, "value", got2.Dynamic["key"])
}

func TestMemNodeCopiesAttrsAndChildren(t *testing.T) {
	child := NewMemNode(MustVPath("/doc#child"), Meta{}, Origin{}, "child", nil, nil)
	attrs := map[string]any{"role": "title"}
	node := NewMemNode(MustVPath("/doc"), Meta{}, Origin{}, "root", attrs, []Node{child})

	attrs["role"] = "mutated"
	gotAttrs := node.Attrs()
	require.Equal(t, "title", gotAttrs["role"])

	gotChildren := node.Children()
	require.Len(t, gotChildren, 1)
	require.Equal(t, "child", gotChildren[0].NodeType())

	gotChildren[0] = NewMemNode(MustVPath("/doc#other"), Meta{}, Origin{}, "other", nil, nil)
	gotChildren2 := node.Children()
	require.Len(t, gotChildren2, 1)
	require.Equal(t, "child", gotChildren2[0].NodeType())
}

func TestMemDocumentOverridesKind(t *testing.T) {
	doc := NewMemDocument(MustVPath("/doc.md"), Meta{}, Origin{}, []byte("# hi"), nil)
	require.Equal(t, KindDocument, doc.Kind())
}

func TestMemArchiveExploded(t *testing.T) {
	archive := NewMemArchive(MustVPath("/a.zip"), Meta{}, Origin{}, []byte("zip"), nil)
	_, ok := archive.Exploded()
	require.False(t, ok)

	folder := NewMemFolder(MustVPath("/a.zip"), Meta{}, Origin{}, nil)
	archive = NewMemArchive(MustVPath("/a.zip"), Meta{}, Origin{}, []byte("zip"), folder)
	exploded, ok := archive.Exploded()
	require.True(t, ok)
	require.Equal(t, KindFolder, exploded.Kind())
}
