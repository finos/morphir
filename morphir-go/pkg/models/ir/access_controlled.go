package ir

// AccessControlled wraps a value with an access level.
//
// This matches Morphir.IR.AccessControlled in finos/morphir-elm.
//
// JSON encoding is versioned and implemented in the codec layer.
type AccessControlled[A any] struct {
	access Access
	value  A
}

// Access represents public or private access.
type Access int

const (
	AccessPublic Access = iota
	AccessPrivate
)

func NewAccessControlled[A any](access Access, value A) AccessControlled[A] {
	return AccessControlled[A]{access: access, value: value}
}

func Public[A any](value A) AccessControlled[A] {
	return NewAccessControlled[A](AccessPublic, value)
}

func Private[A any](value A) AccessControlled[A] {
	return NewAccessControlled[A](AccessPrivate, value)
}

func (ac AccessControlled[A]) Access() Access {
	return ac.access
}

func (ac AccessControlled[A]) Value() A {
	return ac.value
}

// MapAccessControlled applies f to the contained value but preserves access.
func MapAccessControlled[A any, B any](ac AccessControlled[A], f func(A) B) AccessControlled[B] {
	return AccessControlled[B]{access: ac.access, value: f(ac.value)}
}
