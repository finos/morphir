package vfs

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestOverlayWriterMemCreateFile(t *testing.T) {
	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "mem"}, nil)
	vfs := NewOverlayVFS([]Mount{{Name: "mem", Mode: MountRW, Root: root}})

	writer, err := vfs.Writer()
	require.NoError(t, err)

	entry, err := writer.CreateFile(MustVPath("/dir/file.txt"), []byte("data"), WriteOptions{MkdirParents: true})
	require.NoError(t, err)
	require.Equal(t, KindFile, entry.Kind())

	resolved, _, err := vfs.Resolve(MustVPath("/dir/file.txt"))
	require.NoError(t, err)
	file := resolved.(MemFile)
	data, err := file.Bytes()
	require.NoError(t, err)
	require.Equal(t, []byte("data"), data)
}

func TestOverlayWriterMemMove(t *testing.T) {
	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "mem"}, []Entry{
		NewMemFile(MustVPath("/a.txt"), Meta{}, Origin{MountName: "mem"}, []byte("a")),
	})
	vfs := NewOverlayVFS([]Mount{{Name: "mem", Mode: MountRW, Root: root}})

	writer, err := vfs.Writer()
	require.NoError(t, err)

	moved, err := writer.Move(MustVPath("/a.txt"), MustVPath("/b.txt"), WriteOptions{Overwrite: true})
	require.NoError(t, err)
	require.Equal(t, MustVPath("/b.txt"), moved.Path())

	_, _, err = vfs.Resolve(MustVPath("/a.txt"))
	require.Error(t, err)
	_, _, err = vfs.Resolve(MustVPath("/b.txt"))
	require.NoError(t, err)
}

func TestOverlayWriterOSCreateAndDelete(t *testing.T) {
	rootDir := t.TempDir()
	mount := NewOSMount("os", MountRW, rootDir, MustVPath("/"))
	vfs := NewOverlayVFS([]Mount{mount})

	writer, err := vfs.Writer()
	require.NoError(t, err)

	entry, err := writer.CreateFile(MustVPath("/file.txt"), []byte("hi"), WriteOptions{})
	require.NoError(t, err)
	require.Equal(t, KindFile, entry.Kind())

	path := filepath.Join(rootDir, "file.txt")
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	require.Equal(t, []byte("hi"), data)

	_, err = writer.Delete(MustVPath("/file.txt"))
	require.NoError(t, err)
	_, err = os.Stat(path)
	require.Error(t, err)
}

func TestWriterForMount(t *testing.T) {
	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "mem"}, nil)
	vfs := NewOverlayVFS([]Mount{{Name: "mem", Mode: MountRW, Root: root}})

	writer, err := vfs.WriterForMount("mem")
	require.NoError(t, err)
	_, err = writer.CreateFolder(MustVPath("/dir"), WriteOptions{})
	require.NoError(t, err)
}

func TestWriterForMountReadOnly(t *testing.T) {
	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "mem"}, nil)
	vfs := NewOverlayVFS([]Mount{{Name: "mem", Mode: MountRO, Root: root}})

	_, err := vfs.WriterForMount("mem")
	require.Error(t, err)
}
