package vfs

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestOverlayResolve(t *testing.T) {
	low := NewMemFolder(
		MustVPath("/"),
		Meta{},
		Origin{MountName: "low"},
		[]Entry{
			NewMemFile(MustVPath("/a.txt"), Meta{}, Origin{MountName: "low"}, []byte("low")),
		},
	)
	high := NewMemFolder(
		MustVPath("/"),
		Meta{},
		Origin{MountName: "high"},
		[]Entry{
			NewMemFile(MustVPath("/a.txt"), Meta{}, Origin{MountName: "high"}, []byte("high")),
		},
	)

	vfs := NewOverlayVFS([]Mount{
		{Name: "low", Mode: MountRO, Root: low},
		{Name: "high", Mode: MountRO, Root: high},
	})

	entry, shadowed, err := vfs.Resolve(MustVPath("/a.txt"))
	require.NoError(t, err)
	require.Equal(t, "high", entry.Origin().MountName)
	require.Len(t, shadowed, 1)
	require.Equal(t, "low", shadowed[0].Entry.Origin().MountName)
	require.Equal(t, "high", shadowed[0].ShadowedBy)
	require.Equal(t, MustVPath("/a.txt"), shadowed[0].VisiblePath)
}

func TestOverlayResolveNotFound(t *testing.T) {
	vfs := NewOverlayVFS(nil)
	_, _, err := vfs.Resolve(MustVPath("/missing"))
	require.Error(t, err)
}

func TestOverlayList(t *testing.T) {
	low := NewMemFolder(
		MustVPath("/"),
		Meta{},
		Origin{MountName: "low"},
		[]Entry{
			NewMemFile(MustVPath("/a.txt"), Meta{}, Origin{MountName: "low"}, nil),
		},
	)
	high := NewMemFolder(
		MustVPath("/"),
		Meta{},
		Origin{MountName: "high"},
		[]Entry{
			NewMemFile(MustVPath("/a.txt"), Meta{}, Origin{MountName: "high"}, nil),
			NewMemFile(MustVPath("/b.txt"), Meta{}, Origin{MountName: "high"}, nil),
		},
	)

	vfs := NewOverlayVFS([]Mount{
		{Name: "low", Mode: MountRO, Root: low},
		{Name: "high", Mode: MountRO, Root: high},
	})

	visible, err := vfs.List(MustVPath("/"), ListOptions{})
	require.NoError(t, err)
	require.Len(t, visible, 2)

	all, err := vfs.List(MustVPath("/"), ListOptions{IncludeShadowed: true})
	require.NoError(t, err)
	require.Len(t, all, 3)
}

func TestOverlayFind(t *testing.T) {
	root := NewMemFolder(
		MustVPath("/"),
		Meta{},
		Origin{MountName: "root"},
		[]Entry{
			NewMemFile(MustVPath("/a.txt"), Meta{}, Origin{MountName: "root"}, nil),
			NewMemFolder(
				MustVPath("/dir"),
				Meta{},
				Origin{MountName: "root"},
				[]Entry{
					NewMemFile(MustVPath("/dir/b.txt"), Meta{}, Origin{MountName: "root"}, nil),
				},
			),
		},
	)

	vfs := NewOverlayVFS([]Mount{
		{Name: "root", Mode: MountRO, Root: root},
	})

	matches, err := vfs.Find(MustGlob("**/*.txt"), FindOptions{})
	require.NoError(t, err)
	require.Len(t, matches, 2)
}

func TestOverlayFindWithOSMount(t *testing.T) {
	rootDir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(rootDir, "a.txt"), []byte("a"), 0644))
	require.NoError(t, os.MkdirAll(filepath.Join(rootDir, "dir"), 0755))
	require.NoError(t, os.WriteFile(filepath.Join(rootDir, "dir", "b.txt"), []byte("b"), 0644))

	mount := NewOSMount("os", MountRO, rootDir, MustVPath("/"))
	vfs := NewOverlayVFS([]Mount{mount})

	matches, err := vfs.Find(MustGlob("**/*.txt"), FindOptions{})
	require.NoError(t, err)
	require.Len(t, matches, 2)
}
