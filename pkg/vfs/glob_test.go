package vfs

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestParseGlob(t *testing.T) {
	t.Run("accepts simple glob", func(t *testing.T) {
		glob, err := ParseGlob("**/*.elm")
		require.NoError(t, err)
		require.Equal(t, "**/*.elm", glob.String())
	})

	t.Run("rejects empty glob", func(t *testing.T) {
		_, err := ParseGlob("")
		require.Error(t, err)
	})

	t.Run("rejects backslashes", func(t *testing.T) {
		_, err := ParseGlob(`**\\*.elm`)
		require.Error(t, err)
	})
}

func TestMustGlob(t *testing.T) {
	require.Equal(t, "**/*.elm", MustGlob("**/*.elm").String())
	require.Panics(t, func() {
		_ = MustGlob("")
	})
}
