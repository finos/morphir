package vfs

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
)

func buildTestTree() Entry {
	// Build a tree structure:
	// /root
	//   /root/a.txt (file)
	//   /root/b (folder)
	//     /root/b/c.txt (file)
	//     /root/b/d.txt (file)
	//   /root/e.txt (file)

	origin := Origin{MountName: "test"}
	meta := Meta{Dynamic: map[string]any{}, Typed: map[string]any{}}

	fileA := NewMemFile(MustVPath("/root/a.txt"), meta, origin, []byte("a"))
	fileC := NewMemFile(MustVPath("/root/b/c.txt"), meta, origin, []byte("c"))
	fileD := NewMemFile(MustVPath("/root/b/d.txt"), meta, origin, []byte("d"))
	fileE := NewMemFile(MustVPath("/root/e.txt"), meta, origin, []byte("e"))

	folderB := NewMemFolder(MustVPath("/root/b"), meta, origin, []Entry{fileC, fileD})
	root := NewMemFolder(MustVPath("/root"), meta, origin, []Entry{fileA, folderB, fileE})

	return root
}

func TestWalkPreOrder(t *testing.T) {
	tree := buildTestTree()
	var visited []string

	err := Walk(tree, func(e Entry) (WalkControl, error) {
		visited = append(visited, e.Path().String())
		return WalkContinue, nil
	}, nil)

	require.NoError(t, err)
	require.Equal(t, []string{"/root", "/root/a.txt", "/root/b", "/root/b/c.txt", "/root/b/d.txt", "/root/e.txt"}, visited)
}

func TestWalkPostOrder(t *testing.T) {
	tree := buildTestTree()
	var visited []string

	err := Walk(tree, nil, func(e Entry) (WalkControl, error) {
		visited = append(visited, e.Path().String())
		return WalkContinue, nil
	})

	require.NoError(t, err)
	require.Equal(t, []string{"/root/a.txt", "/root/b/c.txt", "/root/b/d.txt", "/root/b", "/root/e.txt", "/root"}, visited)
}

func TestWalkBothCallbacks(t *testing.T) {
	tree := buildTestTree()
	var preVisits []string
	var postVisits []string

	err := Walk(tree,
		func(e Entry) (WalkControl, error) {
			preVisits = append(preVisits, e.Path().String())
			return WalkContinue, nil
		},
		func(e Entry) (WalkControl, error) {
			postVisits = append(postVisits, e.Path().String())
			return WalkContinue, nil
		},
	)

	require.NoError(t, err)
	require.Len(t, preVisits, 6)
	require.Len(t, postVisits, 6)
}

func TestWalkSkip(t *testing.T) {
	tree := buildTestTree()
	var visited []string

	err := Walk(tree, func(e Entry) (WalkControl, error) {
		visited = append(visited, e.Path().String())
		// Skip the /root/b folder's children
		if e.Path().String() == "/root/b" {
			return WalkSkip, nil
		}
		return WalkContinue, nil
	}, nil)

	require.NoError(t, err)
	// Should visit root, a.txt, b (but not b's children), and e.txt
	require.Equal(t, []string{"/root", "/root/a.txt", "/root/b", "/root/e.txt"}, visited)
}

func TestWalkSkipCallsPostFn(t *testing.T) {
	tree := buildTestTree()
	var postVisits []string

	err := Walk(tree,
		func(e Entry) (WalkControl, error) {
			if e.Path().String() == "/root/b" {
				return WalkSkip, nil
			}
			return WalkContinue, nil
		},
		func(e Entry) (WalkControl, error) {
			postVisits = append(postVisits, e.Path().String())
			return WalkContinue, nil
		},
	)

	require.NoError(t, err)
	// Post-order should still be called for /root/b even though we skipped children
	require.Equal(t, []string{"/root/a.txt", "/root/b", "/root/e.txt", "/root"}, postVisits)
}

func TestWalkStop(t *testing.T) {
	tree := buildTestTree()
	var visited []string

	err := Walk(tree, func(e Entry) (WalkControl, error) {
		visited = append(visited, e.Path().String())
		// Stop after visiting /root/b
		if e.Path().String() == "/root/b" {
			return WalkStop, nil
		}
		return WalkContinue, nil
	}, nil)

	require.NoError(t, err)
	// Should only visit up to /root/b
	require.Equal(t, []string{"/root", "/root/a.txt", "/root/b"}, visited)
}

func TestWalkError(t *testing.T) {
	tree := buildTestTree()
	expectedErr := errors.New("test error")

	err := Walk(tree, func(e Entry) (WalkControl, error) {
		if e.Path().String() == "/root/b" {
			return WalkStop, expectedErr
		}
		return WalkContinue, nil
	}, nil)

	require.ErrorIs(t, err, expectedErr)
}

func TestFilter(t *testing.T) {
	tree := buildTestTree()

	// Filter for files only
	results, err := Filter(tree, func(e Entry) (bool, error) {
		return e.Kind() == KindFile, nil
	})

	require.NoError(t, err)
	require.Len(t, results, 4)

	expectedPaths := []string{"/root/a.txt", "/root/b/c.txt", "/root/b/d.txt", "/root/e.txt"}
	for i, exp := range expectedPaths {
		require.Equal(t, exp, results[i].Path().String())
	}
}

func TestFilterFolders(t *testing.T) {
	tree := buildTestTree()

	// Filter for folders only
	results, err := Filter(tree, func(e Entry) (bool, error) {
		return e.Kind() == KindFolder, nil
	})

	require.NoError(t, err)
	require.Len(t, results, 2)

	expectedPaths := []string{"/root", "/root/b"}
	for i, exp := range expectedPaths {
		require.Equal(t, exp, results[i].Path().String())
	}
}

func TestFilterError(t *testing.T) {
	tree := buildTestTree()
	expectedErr := errors.New("filter error")

	_, err := Filter(tree, func(e Entry) (bool, error) {
		if e.Path().String() == "/root/b" {
			return false, expectedErr
		}
		return true, nil
	})

	require.ErrorIs(t, err, expectedErr)
}

func TestMapSame(t *testing.T) {
	tree := buildTestTree()

	// Add a tag to metadata of all entries
	result, err := MapSame(tree, func(e Entry) (Entry, error) {
		meta := e.Meta()
		if meta.Dynamic == nil {
			meta.Dynamic = make(map[string]any)
		}
		meta.Dynamic["tagged"] = true

		// Reconstruct based on kind
		switch e.Kind() {
		case KindFile:
			if file, ok := e.(MemFile); ok {
				data, _ := file.Bytes()
				return NewMemFile(file.Path(), meta, file.Origin(), data), nil
			}
		case KindFolder:
			if folder, ok := e.(MemFolder); ok {
				children, _ := folder.Children()
				return NewMemFolder(folder.Path(), meta, folder.Origin(), children), nil
			}
		}
		return e, nil
	})

	require.NoError(t, err)

	// Verify all entries have the tag
	var count int
	_ = Walk(result, func(e Entry) (WalkControl, error) {
		require.Equal(t, true, e.Meta().Dynamic["tagged"], "entry %s missing tag", e.Path().String())
		count++
		return WalkContinue, nil
	}, nil)

	require.Equal(t, 6, count)
}

func TestMapSameError(t *testing.T) {
	tree := buildTestTree()
	expectedErr := errors.New("map error")

	_, err := MapSame(tree, func(e Entry) (Entry, error) {
		if e.Path().String() == "/root/b/c.txt" {
			return nil, expectedErr
		}
		return e, nil
	})

	require.ErrorIs(t, err, expectedErr)
}

func TestMap(t *testing.T) {
	tree := buildTestTree()

	// Transform all files to have doubled content
	result, err := Map(tree, func(e Entry) (Entry, error) {
		if file, ok := e.(MemFile); ok {
			data, _ := file.Bytes()
			// Double the data
			newData := append(data, data...)
			return NewMemFile(file.Path(), file.Meta(), file.Origin(), newData), nil
		}
		return e, nil
	})

	require.NoError(t, err)

	// Check that files have doubled data
	_, _ = Filter(result, func(e Entry) (bool, error) {
		if e.Kind() == KindFile {
			if file, ok := e.(File); ok {
				data, _ := file.Bytes()
				// Original files had 1 byte, transformed should have 2
				require.Equal(t, 2, len(data), "file %s should have 2 bytes", e.Path().String())
			}
		}
		return false, nil
	})
}

func TestMapError(t *testing.T) {
	tree := buildTestTree()
	expectedErr := errors.New("map error")

	_, err := Map(tree, func(e Entry) (Entry, error) {
		if e.Path().String() == "/root/e.txt" {
			return nil, expectedErr
		}
		return e, nil
	})

	require.ErrorIs(t, err, expectedErr)
}

func TestFold(t *testing.T) {
	tree := buildTestTree()

	// Count total entries
	count, err := Fold(tree, 0, func(acc int, e Entry) (int, error) {
		return acc + 1, nil
	})

	require.NoError(t, err)
	require.Equal(t, 6, count)
}

func TestFoldAccumulatePaths(t *testing.T) {
	tree := buildTestTree()

	// Accumulate all paths
	paths, err := Fold(tree, []string{}, func(acc []string, e Entry) ([]string, error) {
		return append(acc, e.Path().String()), nil
	})

	require.NoError(t, err)
	require.Equal(t, []string{"/root", "/root/a.txt", "/root/b", "/root/b/c.txt", "/root/b/d.txt", "/root/e.txt"}, paths)
}

func TestFoldError(t *testing.T) {
	tree := buildTestTree()
	expectedErr := errors.New("fold error")

	_, err := Fold(tree, 0, func(acc int, e Entry) (int, error) {
		if e.Path().String() == "/root/b" {
			return acc, expectedErr
		}
		return acc + 1, nil
	})

	require.ErrorIs(t, err, expectedErr)
}

func TestFoldFileCount(t *testing.T) {
	tree := buildTestTree()

	// Count only files
	fileCount, err := Fold(tree, 0, func(acc int, e Entry) (int, error) {
		if e.Kind() == KindFile {
			return acc + 1, nil
		}
		return acc, nil
	})

	require.NoError(t, err)
	require.Equal(t, 4, fileCount)
}
