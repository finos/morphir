package ir

// Documented wraps a value with its documentation string.
//
// This matches Morphir.IR.Documented in finos/morphir-elm.
//
// JSON encoding is versioned and implemented in the codec layer.
type Documented[A any] struct {
	doc   string
	value A
}

// NewDocumented creates a new Documented value.
func NewDocumented[A any](doc string, value A) Documented[A] {
	return Documented[A]{doc: doc, value: value}
}

// Doc returns the documentation string.
func (d Documented[A]) Doc() string {
	return d.doc
}

// Value returns the wrapped value.
func (d Documented[A]) Value() A {
	return d.value
}

// MapDocumented applies f to the contained value but preserves the documentation.
func MapDocumented[A any, B any](d Documented[A], f func(A) B) Documented[B] {
	return Documented[B]{doc: d.doc, value: f(d.value)}
}
