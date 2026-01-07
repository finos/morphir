package vfs

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func setupTraverseTestVFS() VFS {
	// Create a test filesystem:
	// /
	//   workspace/
	//     src/
	//       main.go
	//       utils/
	//         helper.go
	//     test/
	//       main_test.go
	//   config/
	//     app.json

	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "test"}, []Entry{
		NewMemFolder(MustVPath("/workspace"), Meta{}, Origin{MountName: "test"}, []Entry{
			NewMemFolder(MustVPath("/workspace/src"), Meta{}, Origin{MountName: "test"}, []Entry{
				NewMemFile(MustVPath("/workspace/src/main.go"), Meta{}, Origin{MountName: "test"}, []byte("package main")),
				NewMemFolder(MustVPath("/workspace/src/utils"), Meta{}, Origin{MountName: "test"}, []Entry{
					NewMemFile(MustVPath("/workspace/src/utils/helper.go"), Meta{}, Origin{MountName: "test"}, []byte("package utils")),
				}),
			}),
			NewMemFolder(MustVPath("/workspace/test"), Meta{}, Origin{MountName: "test"}, []Entry{
				NewMemFile(MustVPath("/workspace/test/main_test.go"), Meta{}, Origin{MountName: "test"}, []byte("package main_test")),
			}),
		}),
		NewMemFolder(MustVPath("/config"), Meta{}, Origin{MountName: "test"}, []Entry{
			NewMemFile(MustVPath("/config/app.json"), Meta{}, Origin{MountName: "test"}, []byte("{}")),
		}),
	})

	return NewOverlayVFS([]Mount{{Name: "test", Mode: MountRW, Root: root}})
}

func TestVFSWalk(t *testing.T) {
	vfs := setupTraverseTestVFS()

	var paths []string
	err := VFSWalk(vfs, MustVPath("/workspace"), VFSWalkOptions{},
		func(e Entry, shadowed bool) (WalkControl, error) {
			paths = append(paths, e.Path().String())
			return WalkContinue, nil
		},
		nil,
	)

	require.NoError(t, err)
	require.Contains(t, paths, "/workspace")
	require.Contains(t, paths, "/workspace/src")
	require.Contains(t, paths, "/workspace/src/main.go")
	require.Contains(t, paths, "/workspace/src/utils")
	require.Contains(t, paths, "/workspace/src/utils/helper.go")
	require.Contains(t, paths, "/workspace/test")
	require.Contains(t, paths, "/workspace/test/main_test.go")
}

func TestVFSWalkPostOrder(t *testing.T) {
	vfs := setupTraverseTestVFS()

	var prePaths []string
	var postPaths []string

	err := VFSWalk(vfs, MustVPath("/workspace/src"),
		VFSWalkOptions{},
		func(e Entry, shadowed bool) (WalkControl, error) {
			prePaths = append(prePaths, e.Path().String())
			return WalkContinue, nil
		},
		func(e Entry, shadowed bool) (WalkControl, error) {
			postPaths = append(postPaths, e.Path().String())
			return WalkContinue, nil
		},
	)

	require.NoError(t, err)

	// Pre-order should visit folder before children
	require.Equal(t, "/workspace/src", prePaths[0])

	// Post-order should visit children before folder
	require.Equal(t, "/workspace/src", postPaths[len(postPaths)-1])
}

func TestVFSWalkSkip(t *testing.T) {
	vfs := setupTraverseTestVFS()

	var paths []string
	err := VFSWalk(vfs, MustVPath("/workspace"),
		VFSWalkOptions{},
		func(e Entry, shadowed bool) (WalkControl, error) {
			paths = append(paths, e.Path().String())
			// Skip the src directory and its children
			if e.Path().String() == "/workspace/src" {
				return WalkSkip, nil
			}
			return WalkContinue, nil
		},
		nil,
	)

	require.NoError(t, err)
	require.Contains(t, paths, "/workspace")
	require.Contains(t, paths, "/workspace/src")
	// Should not contain src's children
	require.NotContains(t, paths, "/workspace/src/main.go")
	require.NotContains(t, paths, "/workspace/src/utils")
	// Should still contain test directory
	require.Contains(t, paths, "/workspace/test")
}

func TestVFSWalkStop(t *testing.T) {
	vfs := setupTraverseTestVFS()

	var paths []string
	err := VFSWalk(vfs, MustVPath("/workspace"),
		VFSWalkOptions{},
		func(e Entry, shadowed bool) (WalkControl, error) {
			paths = append(paths, e.Path().String())
			// Stop when we hit main.go
			if e.Path().String() == "/workspace/src/main.go" {
				return WalkStop, nil
			}
			return WalkContinue, nil
		},
		nil,
	)

	require.NoError(t, err)
	require.Contains(t, paths, "/workspace/src/main.go")
	// Should not continue to utils after stopping
	require.NotContains(t, paths, "/workspace/src/utils")
}

func TestVFSCollect(t *testing.T) {
	vfs := setupTraverseTestVFS()

	entries, err := VFSCollect(vfs, MustVPath("/workspace/src"), VFSWalkOptions{})
	require.NoError(t, err)

	// Should collect src folder, main.go, utils folder, helper.go
	require.Len(t, entries, 4)

	paths := make([]string, len(entries))
	for i, e := range entries {
		paths[i] = e.Path().String()
	}

	require.Contains(t, paths, "/workspace/src")
	require.Contains(t, paths, "/workspace/src/main.go")
	require.Contains(t, paths, "/workspace/src/utils")
	require.Contains(t, paths, "/workspace/src/utils/helper.go")
}

func TestVFSFilter(t *testing.T) {
	vfs := setupTraverseTestVFS()

	// Filter for .go files
	goFiles, err := VFSFilter(vfs, MustVPath("/workspace"), VFSWalkOptions{},
		func(e Entry) (bool, error) {
			path := e.Path().String()
			return len(path) > 3 && path[len(path)-3:] == ".go", nil
		},
	)

	require.NoError(t, err)
	require.Len(t, goFiles, 3) // main.go, helper.go, main_test.go

	paths := make([]string, len(goFiles))
	for i, f := range goFiles {
		paths[i] = f.Path().String()
	}

	require.Contains(t, paths, "/workspace/src/main.go")
	require.Contains(t, paths, "/workspace/src/utils/helper.go")
	require.Contains(t, paths, "/workspace/test/main_test.go")
}

func TestVFSFindByKind(t *testing.T) {
	vfs := setupTraverseTestVFS()

	files, err := VFSFindByKind(vfs, MustVPath("/workspace"), KindFile, VFSWalkOptions{})
	require.NoError(t, err)
	require.Len(t, files, 3) // main.go, helper.go, main_test.go

	folders, err := VFSFindByKind(vfs, MustVPath("/workspace"), KindFolder, VFSWalkOptions{})
	require.NoError(t, err)
	require.Len(t, folders, 4) // workspace, src, utils, test
}

func TestVFSFindFiles(t *testing.T) {
	vfs := setupTraverseTestVFS()

	files, err := VFSFindFiles(vfs, MustVPath("/workspace"), VFSWalkOptions{})
	require.NoError(t, err)
	require.Len(t, files, 3)

	// All should implement File interface
	for _, f := range files {
		_, err := f.Bytes()
		require.NoError(t, err)
	}
}

func TestVFSFindFolders(t *testing.T) {
	vfs := setupTraverseTestVFS()

	folders, err := VFSFindFolders(vfs, MustVPath("/workspace"), VFSWalkOptions{})
	require.NoError(t, err)
	require.Len(t, folders, 4)

	// All should implement Folder interface
	for _, f := range folders {
		_, err := f.Children()
		require.NoError(t, err)
	}
}

func TestVFSMap(t *testing.T) {
	vfs := setupTraverseTestVFS()

	// Map all entries to their paths
	paths, err := VFSMap(vfs, MustVPath("/workspace/src"), VFSWalkOptions{},
		func(e Entry, shadowed bool) (string, error) {
			return e.Path().String(), nil
		},
	)

	require.NoError(t, err)
	require.Len(t, paths, 4)
	require.Contains(t, paths, "/workspace/src")
	require.Contains(t, paths, "/workspace/src/main.go")
	require.Contains(t, paths, "/workspace/src/utils")
	require.Contains(t, paths, "/workspace/src/utils/helper.go")
}

func TestVFSFold(t *testing.T) {
	vfs := setupTraverseTestVFS()

	// Count total file size
	totalSize, err := VFSFold(vfs, MustVPath("/workspace"), VFSWalkOptions{}, 0,
		func(acc int, e Entry, shadowed bool) (int, error) {
			if file, ok := e.(File); ok {
				data, err := file.Bytes()
				if err != nil {
					return acc, err
				}
				return acc + len(data), nil
			}
			return acc, nil
		},
	)

	require.NoError(t, err)
	// package main + package utils + package main_test
	expectedSize := len("package main") + len("package utils") + len("package main_test")
	require.Equal(t, expectedSize, totalSize)
}

func TestVFSCountEntries(t *testing.T) {
	vfs := setupTraverseTestVFS()

	count, err := VFSCountEntries(vfs, MustVPath("/workspace"), VFSWalkOptions{})
	require.NoError(t, err)
	// workspace, src, main.go, utils, helper.go, test, main_test.go = 7
	require.Equal(t, 7, count)

	count, err = VFSCountEntries(vfs, MustVPath("/workspace/src"), VFSWalkOptions{})
	require.NoError(t, err)
	// src, main.go, utils, helper.go = 4
	require.Equal(t, 4, count)
}

func TestVFSWalkWithShadowed(t *testing.T) {
	// Create a VFS with shadowed entries
	lowerRoot := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "lower"}, []Entry{
		NewMemFile(MustVPath("/file.txt"), Meta{}, Origin{MountName: "lower"}, []byte("lower")),
	})

	upperRoot := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "upper"}, []Entry{
		NewMemFile(MustVPath("/file.txt"), Meta{}, Origin{MountName: "upper"}, []byte("upper")),
	})

	vfs := NewOverlayVFS([]Mount{
		{Name: "lower", Mode: MountRO, Root: lowerRoot},
		{Name: "upper", Mode: MountRW, Root: upperRoot},
	})

	// Without shadowed
	var paths []string
	err := VFSWalk(vfs, MustVPath("/"), VFSWalkOptions{IncludeShadowed: false},
		func(e Entry, shadowed bool) (WalkControl, error) {
			paths = append(paths, e.Path().String())
			return WalkContinue, nil
		},
		nil,
	)

	require.NoError(t, err)
	require.Len(t, paths, 2) // root and file.txt from upper

	// With shadowed
	paths = nil
	var shadowedCount int
	err = VFSWalk(vfs, MustVPath("/"), VFSWalkOptions{IncludeShadowed: true},
		func(e Entry, shadowed bool) (WalkControl, error) {
			paths = append(paths, e.Path().String())
			if shadowed {
				shadowedCount++
			}
			return WalkContinue, nil
		},
		nil,
	)

	require.NoError(t, err)
	require.Len(t, paths, 4)           // root (both), file.txt (both)
	require.Equal(t, 2, shadowedCount) // root and file.txt from lower
}

func TestVFSCollectGlob(t *testing.T) {
	vfs := setupTraverseTestVFS()

	// Find all .go files
	goFiles, err := VFSCollectGlob(vfs, MustGlob("**/*.go"), VFSWalkOptions{})
	require.NoError(t, err)
	require.Len(t, goFiles, 3)

	paths := make([]string, len(goFiles))
	for i, f := range goFiles {
		paths[i] = f.Path().String()
	}

	require.Contains(t, paths, "/workspace/src/main.go")
	require.Contains(t, paths, "/workspace/src/utils/helper.go")
	require.Contains(t, paths, "/workspace/test/main_test.go")
}
