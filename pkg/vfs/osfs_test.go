package vfs

import (
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestOSFolderChildren(t *testing.T) {
	rootDir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(rootDir, "a.txt"), []byte("a"), 0644))

	subDir := filepath.Join(rootDir, "dir")
	require.NoError(t, os.MkdirAll(subDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(subDir, "b.txt"), []byte("b"), 0644))

	folder := NewOSFolder(MustVPath("/"), Meta{}, Origin{MountName: "os"}, rootDir)
	children, err := folder.Children()
	require.NoError(t, err)
	require.Len(t, children, 2)

	var fileEntry Entry
	var dirEntry Entry
	for _, child := range children {
		switch child.Kind() {
		case KindFile:
			fileEntry = child
		case KindFolder:
			dirEntry = child
		}
	}

	require.NotNil(t, fileEntry)
	require.Equal(t, MustVPath("/a.txt"), fileEntry.Path())

	require.NotNil(t, dirEntry)
	require.Equal(t, MustVPath("/dir"), dirEntry.Path())

	dirFolder, ok := dirEntry.(Folder)
	require.True(t, ok)
	dirChildren, err := dirFolder.Children()
	require.NoError(t, err)
	require.Len(t, dirChildren, 1)
	require.Equal(t, MustVPath("/dir/b.txt"), dirChildren[0].Path())
}

func TestOSFolderChildMetadata(t *testing.T) {
	rootDir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(rootDir, "a.txt"), []byte("a"), 0644))

	parentMeta := Meta{
		Dynamic: map[string]any{"parent": "value"},
	}
	folder := NewOSFolder(MustVPath("/"), parentMeta, Origin{MountName: "os"}, rootDir)
	children, err := folder.Children()
	require.NoError(t, err)
	require.Len(t, children, 1)

	childMeta := children[0].Meta()
	require.Equal(t, "value", childMeta.Dynamic["parent"])
	require.Equal(t, filepath.Join(rootDir, "a.txt"), childMeta.Dynamic["os.path"])
	require.Equal(t, false, childMeta.Dynamic["os.is_dir"])
}

func TestOSFileBytesAndStream(t *testing.T) {
	rootDir := t.TempDir()
	path := filepath.Join(rootDir, "file.txt")
	require.NoError(t, os.WriteFile(path, []byte("data"), 0644))

	file := NewOSFile(MustVPath("/file.txt"), Meta{}, Origin{MountName: "os"}, path)
	data, err := file.Bytes()
	require.NoError(t, err)
	require.Equal(t, []byte("data"), data)

	reader, err := file.Stream()
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, reader.Close())
	})
	buf, err := io.ReadAll(reader)
	require.NoError(t, err)
	require.Equal(t, []byte("data"), buf)
}
