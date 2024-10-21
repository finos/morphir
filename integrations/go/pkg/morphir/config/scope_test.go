package config

import "testing"

func TestNewScope(t *testing.T) {
	t.Run("New Scope with no additional options should be User scoped", func(t *testing.T) {
		sut := NewScope()
		actual := sut.IsUser()
		if actual != true {
			t.Errorf("IsUser() = %t, want %t", actual, true)
		}
	})

	t.Run("New Scope with no additional options should not be System scoped", func(t *testing.T) {
		sut := NewScope()
		actual := sut.IsSystem()
		if actual != false {
			t.Errorf("IsSystem() = %t, want %t", actual, false)
		}
	})
}
