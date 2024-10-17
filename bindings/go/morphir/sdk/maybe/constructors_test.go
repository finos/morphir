package maybe

import (
	"github.com/stretchr/testify/assert"
	"testing"
)

type Person struct {
	Name string
	Age  int
}

func TestNew(t *testing.T) {
	s := New[*Person](nil)

	assert.True(t, s.IsEmpty())

}

func TestNothing(t *testing.T) {
	str := Nothing[string]()

	assert.True(t, str.IsEmpty())
	assert.Equal(t, "", str.value)

	i := Nothing[int]()
	assert.True(t, i.IsEmpty())
	assert.Equal(t, 0, i.value)

	err := Nothing[error]()
	assert.True(t, err.IsEmpty())
	assert.Nil(t, err.value)
}

func TestJust(t *testing.T) {
	value := "hello"
	sut := Just(value)

	assert.True(t, !sut.IsEmpty())
	assert.Equal(t, value, sut.value)
}
