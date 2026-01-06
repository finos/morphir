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
