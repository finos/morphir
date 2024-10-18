package maybe

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMaybe_WithDefault(t *testing.T) {
	t.Run("When Maybe is Nothing", func(t *testing.T) {
		sut := Nothing[[]string]()

		actual := WithDefault([]string{})(sut)
		assert.Equal(t, []string{}, actual)
	})
}
