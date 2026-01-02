package ir

import "fmt"

// Pattern represents the Morphir IR Pattern tree.
//
// In the upstream Morphir IR (Elm), Pattern is parameterized by an attribute type `a`.
// Those attributes are carried at every node (e.g. source locations, inferred info).
// In Go we model that with a type parameter `A`.
//
// JSON encoding is versioned and implemented in the codec layer
// (see pkg/models/stable/ir/codec/json).
//
// Pattern is a sum type; concrete variants include WildcardPattern, AsPattern, etc.
// The interface is intentionally small: callers typically pattern-match using a
// type switch (or implement a helper similar to MatchType).
//
// All variants use unexported fields and provide accessors to preserve
// immutability/value semantics.
//
// See also: Morphir.IR.Value.Pattern in finos/morphir-elm.
type Pattern[A any] interface {
	isPattern()
	Attributes() A
}

// WildcardPattern corresponds to: WildcardPattern a
//
// Matches any value and does not extract variables.
type WildcardPattern[A any] struct {
	attributes A
}

func NewWildcardPattern[A any](attributes A) Pattern[A] {
	return WildcardPattern[A]{attributes: attributes}
}

func (WildcardPattern[A]) isPattern() {}

func (p WildcardPattern[A]) Attributes() A { return p.attributes }

// AsPattern corresponds to: AsPattern a (Pattern a) Name
//
// Assigns a variable name to the value matched by a nested pattern.
type AsPattern[A any] struct {
	attributes A
	subject    Pattern[A]
	name       Name
}

func NewAsPattern[A any](attributes A, subject Pattern[A], name Name) Pattern[A] {
	return AsPattern[A]{attributes: attributes, subject: subject, name: name}
}

func (AsPattern[A]) isPattern() {}

func (p AsPattern[A]) Attributes() A { return p.attributes }

func (p AsPattern[A]) Subject() Pattern[A] { return p.subject }

func (p AsPattern[A]) Name() Name { return p.name }

// TuplePattern corresponds to: TuplePattern a (List (Pattern a))
type TuplePattern[A any] struct {
	attributes A
	elements   []Pattern[A]
}

func NewTuplePattern[A any](attributes A, elements []Pattern[A]) Pattern[A] {
	var copied []Pattern[A]
	if len(elements) > 0 {
		copied = make([]Pattern[A], len(elements))
		copy(copied, elements)
	}
	return TuplePattern[A]{attributes: attributes, elements: copied}
}

func (TuplePattern[A]) isPattern() {}

func (p TuplePattern[A]) Attributes() A { return p.attributes }

func (p TuplePattern[A]) Elements() []Pattern[A] {
	if len(p.elements) == 0 {
		return nil
	}
	copied := make([]Pattern[A], len(p.elements))
	copy(copied, p.elements)
	return copied
}

// ConstructorPattern corresponds to: ConstructorPattern a FQName (List (Pattern a))
type ConstructorPattern[A any] struct {
	attributes A
	name       FQName
	args       []Pattern[A]
}

func NewConstructorPattern[A any](attributes A, name FQName, args []Pattern[A]) Pattern[A] {
	var copied []Pattern[A]
	if len(args) > 0 {
		copied = make([]Pattern[A], len(args))
		copy(copied, args)
	}
	return ConstructorPattern[A]{attributes: attributes, name: name, args: copied}
}

func (ConstructorPattern[A]) isPattern() {}

func (p ConstructorPattern[A]) Attributes() A { return p.attributes }

func (p ConstructorPattern[A]) ConstructorName() FQName { return p.name }

func (p ConstructorPattern[A]) Args() []Pattern[A] {
	if len(p.args) == 0 {
		return nil
	}
	copied := make([]Pattern[A], len(p.args))
	copy(copied, p.args)
	return copied
}

// EmptyListPattern corresponds to: EmptyListPattern a
type EmptyListPattern[A any] struct {
	attributes A
}

func NewEmptyListPattern[A any](attributes A) Pattern[A] {
	return EmptyListPattern[A]{attributes: attributes}
}

func (EmptyListPattern[A]) isPattern() {}

func (p EmptyListPattern[A]) Attributes() A { return p.attributes }

// HeadTailPattern corresponds to: HeadTailPattern a (Pattern a) (Pattern a)
type HeadTailPattern[A any] struct {
	attributes A
	head       Pattern[A]
	tail       Pattern[A]
}

func NewHeadTailPattern[A any](attributes A, head Pattern[A], tail Pattern[A]) Pattern[A] {
	return HeadTailPattern[A]{attributes: attributes, head: head, tail: tail}
}

func (HeadTailPattern[A]) isPattern() {}

func (p HeadTailPattern[A]) Attributes() A { return p.attributes }

func (p HeadTailPattern[A]) Head() Pattern[A] { return p.head }

func (p HeadTailPattern[A]) Tail() Pattern[A] { return p.tail }

// LiteralPattern corresponds to: LiteralPattern a Literal
type LiteralPattern[A any] struct {
	attributes A
	literal    Literal
}

func NewLiteralPattern[A any](attributes A, literal Literal) Pattern[A] {
	return LiteralPattern[A]{attributes: attributes, literal: literal}
}

func (LiteralPattern[A]) isPattern() {}

func (p LiteralPattern[A]) Attributes() A { return p.attributes }

func (p LiteralPattern[A]) Literal() Literal { return p.literal }

// UnitPattern corresponds to: UnitPattern a
type UnitPattern[A any] struct {
	attributes A
}

func NewUnitPattern[A any](attributes A) Pattern[A] {
	return UnitPattern[A]{attributes: attributes}
}

func (UnitPattern[A]) isPattern() {}

func (p UnitPattern[A]) Attributes() A { return p.attributes }

// EqualPattern performs structural equality between two patterns using the provided
// attribute equality function.
func EqualPattern[A any](eqAttributes func(A, A) bool, left Pattern[A], right Pattern[A]) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return equalPatternConcrete(eqAttributes, left, right)
}

func equalPatternConcrete[A any](eqAttributes func(A, A) bool, left Pattern[A], right Pattern[A]) bool {
	switch l := left.(type) {
	case WildcardPattern[A]:
		r, ok := right.(WildcardPattern[A])
		return ok && eqAttributes(l.attributes, r.attributes)
	case AsPattern[A]:
		r, ok := right.(AsPattern[A])
		return ok && equalAsPattern(eqAttributes, l, r)
	case TuplePattern[A]:
		r, ok := right.(TuplePattern[A])
		return ok && equalTuplePattern(eqAttributes, l, r)
	case ConstructorPattern[A]:
		r, ok := right.(ConstructorPattern[A])
		return ok && equalConstructorPattern(eqAttributes, l, r)
	case EmptyListPattern[A]:
		r, ok := right.(EmptyListPattern[A])
		return ok && eqAttributes(l.attributes, r.attributes)
	case HeadTailPattern[A]:
		r, ok := right.(HeadTailPattern[A])
		return ok && equalHeadTailPattern(eqAttributes, l, r)
	case LiteralPattern[A]:
		r, ok := right.(LiteralPattern[A])
		return ok && eqAttributes(l.attributes, r.attributes) && EqualLiteral(l.literal, r.literal)
	case UnitPattern[A]:
		r, ok := right.(UnitPattern[A])
		return ok && eqAttributes(l.attributes, r.attributes)
	default:
		return false
	}
}

func equalAsPattern[A any](eqAttributes func(A, A) bool, left AsPattern[A], right AsPattern[A]) bool {
	if !eqAttributes(left.attributes, right.attributes) {
		return false
	}
	if !left.name.Equal(right.name) {
		return false
	}
	return EqualPattern(eqAttributes, left.subject, right.subject)
}

func equalTuplePattern[A any](eqAttributes func(A, A) bool, left TuplePattern[A], right TuplePattern[A]) bool {
	if !eqAttributes(left.attributes, right.attributes) {
		return false
	}
	if len(left.elements) != len(right.elements) {
		return false
	}
	for i := range left.elements {
		if !EqualPattern(eqAttributes, left.elements[i], right.elements[i]) {
			return false
		}
	}
	return true
}

func equalConstructorPattern[A any](eqAttributes func(A, A) bool, left ConstructorPattern[A], right ConstructorPattern[A]) bool {
	if !eqAttributes(left.attributes, right.attributes) {
		return false
	}
	if !left.name.Equal(right.name) {
		return false
	}
	if len(left.args) != len(right.args) {
		return false
	}
	for i := range left.args {
		if !EqualPattern(eqAttributes, left.args[i], right.args[i]) {
			return false
		}
	}
	return true
}

func equalHeadTailPattern[A any](eqAttributes func(A, A) bool, left HeadTailPattern[A], right HeadTailPattern[A]) bool {
	if !eqAttributes(left.attributes, right.attributes) {
		return false
	}
	if !EqualPattern(eqAttributes, left.head, right.head) {
		return false
	}
	return EqualPattern(eqAttributes, left.tail, right.tail)
}

// MapPatternAttributes maps the attribute type at each node while preserving the
// Pattern tree structure.
func MapPatternAttributes[A any, B any](p Pattern[A], mapAttributes func(A) B) (Pattern[B], error) {
	if p == nil {
		return nil, fmt.Errorf("ir: Pattern must not be nil")
	}
	if mapAttributes == nil {
		return nil, fmt.Errorf("ir: mapAttributes must not be nil")
	}

	switch v := p.(type) {
	case WildcardPattern[A]:
		return NewWildcardPattern[B](mapAttributes(v.attributes)), nil
	case AsPattern[A]:
		sub, err := MapPatternAttributes[A, B](v.subject, mapAttributes)
		if err != nil {
			return nil, err
		}
		return NewAsPattern[B](mapAttributes(v.attributes), sub, v.name), nil
	case TuplePattern[A]:
		elems, err := mapPatternAttributesList[A, B](v.elements, mapAttributes)
		if err != nil {
			return nil, err
		}
		return NewTuplePattern[B](mapAttributes(v.attributes), elems), nil
	case ConstructorPattern[A]:
		args, err := mapPatternAttributesList[A, B](v.args, mapAttributes)
		if err != nil {
			return nil, err
		}
		return NewConstructorPattern[B](mapAttributes(v.attributes), v.name, args), nil
	case EmptyListPattern[A]:
		return NewEmptyListPattern[B](mapAttributes(v.attributes)), nil
	case HeadTailPattern[A]:
		h, err := MapPatternAttributes[A, B](v.head, mapAttributes)
		if err != nil {
			return nil, err
		}
		t, err := MapPatternAttributes[A, B](v.tail, mapAttributes)
		if err != nil {
			return nil, err
		}
		return NewHeadTailPattern[B](mapAttributes(v.attributes), h, t), nil
	case LiteralPattern[A]:
		return NewLiteralPattern[B](mapAttributes(v.attributes), v.literal), nil
	case UnitPattern[A]:
		return NewUnitPattern[B](mapAttributes(v.attributes)), nil
	default:
		return nil, fmt.Errorf("ir: unsupported Pattern variant %T", p)
	}
}

func mapPatternAttributesList[A any, B any](patterns []Pattern[A], mapAttributes func(A) B) ([]Pattern[B], error) {
	if len(patterns) == 0 {
		return nil, nil
	}
	result := make([]Pattern[B], len(patterns))
	for i := range patterns {
		mapped, err := MapPatternAttributes[A, B](patterns[i], mapAttributes)
		if err != nil {
			return nil, err
		}
		result[i] = mapped
	}
	return result, nil
}
