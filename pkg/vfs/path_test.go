package vfs

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestParseVPath(t *testing.T) {
	t.Run("absolute path normalizes", func(t *testing.T) {
		path, err := ParseVPath("/a/./b//c")
		require.NoError(t, err)
		require.Equal(t, "/a/b/c", path.String())
	})

	t.Run("root path stays root", func(t *testing.T) {
		path, err := ParseVPath("/")
		require.NoError(t, err)
		require.Equal(t, "/", path.String())
	})

	t.Run("relative path normalizes", func(t *testing.T) {
		path, err := ParseVPath("a/./b")
		require.NoError(t, err)
		require.Equal(t, "a/b", path.String())
	})

	t.Run("rejects empty path", func(t *testing.T) {
		_, err := ParseVPath("")
		require.Error(t, err)
	})

	t.Run("rejects empty relative after normalization", func(t *testing.T) {
		_, err := ParseVPath("./")
		require.Error(t, err)
	})

	t.Run("rejects backslashes", func(t *testing.T) {
		_, err := ParseVPath(`a\\b`)
		require.Error(t, err)
	})

	t.Run("rejects escape above root", func(t *testing.T) {
		_, err := ParseVPath("/../a")
		require.Error(t, err)
	})
}

func TestVPathJoin(t *testing.T) {
	base := MustVPath("/a/b")
	joined, err := base.Join("c", "d")
	require.NoError(t, err)
	require.Equal(t, "/a/b/c/d", joined.String())

	relative := MustVPath("a/b")
	relJoined, err := relative.Join("c")
	require.NoError(t, err)
	require.Equal(t, "a/b/c", relJoined.String())
}

func TestMustVPath(t *testing.T) {
	require.Equal(t, "a/b", MustVPath("a/b").String())

	require.Panics(t, func() {
		_ = MustVPath("")
	})
}

func TestVPathIsAbs(t *testing.T) {
	require.True(t, MustVPath("/a/b").IsAbs())
	require.True(t, MustVPath("/").IsAbs())
	require.False(t, MustVPath("a/b").IsAbs())
}

func TestVPathBase(t *testing.T) {
	tests := []struct {
		path string
		want string
	}{
		{"/a/b/c", "c"},
		{"/a", "a"},
		{"/", "/"},
		{"a/b", "b"},
		{"a", "a"},
		{"/file.txt", "file.txt"},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			got := MustVPath(tt.path).Base()
			require.Equal(t, tt.want, got)
		})
	}
}

func TestVPathDir(t *testing.T) {
	tests := []struct {
		path string
		want string
	}{
		{"/a/b/c", "/a/b"},
		{"/a", "/"},
		{"/", "/"},
		{"a/b", "a"},
		{"a", "."},
		{"/workspace/src/main.go", "/workspace/src"},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			got := MustVPath(tt.path).Dir()
			require.Equal(t, tt.want, got.String())
		})
	}
}

func TestVPathExt(t *testing.T) {
	tests := []struct {
		path string
		want string
	}{
		{"/a/b/file.txt", ".txt"},
		{"/a/b/file.tar.gz", ".gz"},
		{"/a/b/file", ""},
		{"/a/b/.dotfile", ""},
		{"/a/b/.dotfile.txt", ".txt"},
		{"file.go", ".go"},
		{"README", ""},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			got := MustVPath(tt.path).Ext()
			require.Equal(t, tt.want, got)
		})
	}
}

func TestVPathStem(t *testing.T) {
	tests := []struct {
		path string
		want string
	}{
		{"/a/b/file.txt", "file"},
		{"/a/b/file.tar.gz", "file.tar"},
		{"/a/b/file", "file"},
		{"/a/b/.dotfile", ".dotfile"},
		{"/a/b/.dotfile.txt", ".dotfile"},
		{"main.go", "main"},
		{"README", "README"},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			got := MustVPath(tt.path).Stem()
			require.Equal(t, tt.want, got)
		})
	}
}

func TestVPathRel(t *testing.T) {
	tests := []struct {
		name   string
		from   string
		to     string
		want   string
		errMsg string
	}{
		{"same path", "/a/b", "/a/b", ".", ""},
		{"sibling", "/a/b", "/a/c", "../c", ""},
		{"child", "/a/b", "/a/b/c", "c", ""},
		{"parent", "/a/b/c", "/a/b", "..", ""},
		{"cousin", "/a/b/c", "/a/d/e", "../../d/e", ""},
		{"deep nesting", "/a/b/c/d", "/a/e/f/g", "../../../e/f/g", ""},
		{"relative paths", "a/b", "a/c", "../c", ""},
		{"mixed abs/rel", "/a/b", "c/d", "", "cannot compute relative path"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			from := MustVPath(tt.from)
			to := MustVPath(tt.to)
			got, err := from.Rel(to)

			if tt.errMsg != "" {
				require.Error(t, err)
				require.Contains(t, err.Error(), tt.errMsg)
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.want, got.String())
			}
		})
	}
}

func TestCommonRoot(t *testing.T) {
	tests := []struct {
		name   string
		paths  []string
		want   string
		errMsg string
	}{
		{
			name:  "single path",
			paths: []string{"/a/b/c"},
			want:  "/a/b/c",
		},
		{
			name:  "siblings",
			paths: []string{"/a/b/c", "/a/b/d"},
			want:  "/a/b",
		},
		{
			name:  "deep common root",
			paths: []string{"/workspace/src/main.go", "/workspace/src/utils/helper.go", "/workspace/test/main_test.go"},
			want:  "/workspace",
		},
		{
			name:  "no common root except /",
			paths: []string{"/a/b", "/c/d"},
			want:  "/",
		},
		{
			name:  "relative paths with common root",
			paths: []string{"a/b/c", "a/b/d", "a/e"},
			want:  "a",
		},
		{
			name:   "empty list",
			paths:  []string{},
			errMsg: "empty path list",
		},
		{
			name:   "mixed absolute and relative",
			paths:  []string{"/a/b", "c/d"},
			errMsg: "mixed absolute and relative",
		},
		{
			name:   "relative paths no common root",
			paths:  []string{"a/b", "c/d"},
			errMsg: "no common root found",
		},
		{
			name:  "identical paths",
			paths: []string{"/a/b/c", "/a/b/c", "/a/b/c"},
			want:  "/a/b/c",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			paths := make([]VPath, len(tt.paths))
			for i, p := range tt.paths {
				paths[i] = MustVPath(p)
			}

			got, err := CommonRoot(paths)

			if tt.errMsg != "" {
				require.Error(t, err)
				require.Contains(t, err.Error(), tt.errMsg)
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.want, got.String())
			}
		})
	}
}
