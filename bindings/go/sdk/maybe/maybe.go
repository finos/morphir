package maybe

type Maybe[T any] struct {
	empty bool
	value T
}

// IsEmpty returns true if the Maybe container has no data
func (m Maybe[T]) IsEmpty() bool { return m.empty }

// Get returns
func (m Maybe[T]) Get() (value T, isPresent bool) {
	return m.value, !m.empty
}
