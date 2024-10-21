package list

import (
	"github.com/finos/morphir/corelib/go/morphir/sdk/basics"
	"github.com/stretchr/testify/assert"
	"testing"
)

func TestList_Singleton(t *testing.T) {
	t.Run("String singleton", func(t *testing.T) {
		var expected List[string] = []string{"lorem ipsum"}
		actual := Singleton("lorem ipsum")

		assert.Equal(t, expected, actual)
	})
}

func TestList_Repeat(t *testing.T) {
	t.Run("Repeating Int 42, 5 times", func(t *testing.T) {
		actual := Repeat[basics.Int](basics.Int(5))(basics.Int(42))
		expected := List[basics.Int]{42, 42, 42, 42, 42}
		assert.Equal(t, expected, actual)
	})
}
