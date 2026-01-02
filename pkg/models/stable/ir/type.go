package ir

// Type represents the Morphir IR Type tree.
//
// In the upstream Morphir IR (Elm), Type is parameterized by an attribute type `a`.
// Those attributes are carried at every node (e.g. source locations, inferred info,
// annotations). In Go we model that with a type parameter `A`.
//
// JSON encoding is versioned and implemented in the codec layer
// (see pkg/models/stable/ir/codec/json).
//
// Note: This package aims to keep the domain model stable and independent of any
// particular encoding (JSON/YAML/etc.).
//
// Type is a sum type; concrete variants include TypeVariable, TypeReference, etc.
//
// The interface is intentionally small: callers typically pattern-match using a
// type switch.
//
// All variants use unexported fields and provide accessors to preserve
// immutability/value semantics.
//
// See also: Morphir.IR.Type in finos/morphir-elm.
//
//go:generate go test ./...
// (go:generate line is a no-op convenience for editors; generation is not required.)

type Type[A any] interface {
	isType()
	Attributes() A
}

// Field represents a record field type: { name : Name, tpe : Type a }.
//
// In JSON:
//   - v1: [ name, tpe ]
//   - v2/v3: { "name": name, "tpe": tpe }
//
// Field does not implement encoding/json hook methods; encoding is handled by
// the codec layer.
type Field[A any] struct {
	name Name
	tpe  Type[A]
}

// FieldFromParts constructs a field.
func FieldFromParts[A any](name Name, tpe Type[A]) Field[A] {
	return Field[A]{name: name, tpe: tpe}
}

func (f Field[A]) Name() Name {
	return f.name
}

func (f Field[A]) Type() Type[A] {
	return f.tpe
}

// TypeVariable corresponds to: Variable a Name
//
// Represents a type variable.
type TypeVariable[A any] struct {
	attributes A
	name       Name
}

func NewTypeVariable[A any](attributes A, name Name) Type[A] {
	return TypeVariable[A]{attributes: attributes, name: name}
}

func (TypeVariable[A]) isType() {
	// Marker method for the Type sum type.
}

func (t TypeVariable[A]) Attributes() A {
	return t.attributes
}

func (t TypeVariable[A]) Name() Name {
	return t.name
}

// TypeReference corresponds to: Reference a FQName (List (Type a))
//
// Represents a type reference and its type parameters.
type TypeReference[A any] struct {
	attributes     A
	fullyQualified FQName
	typeParams     []Type[A]
}

func NewTypeReference[A any](attributes A, fullyQualified FQName, typeParams []Type[A]) Type[A] {
	var copied []Type[A]
	if len(typeParams) > 0 {
		copied = make([]Type[A], len(typeParams))
		copy(copied, typeParams)
	}
	return TypeReference[A]{attributes: attributes, fullyQualified: fullyQualified, typeParams: copied}
}

func (TypeReference[A]) isType() {
	// Marker method for the Type sum type.
}

func (t TypeReference[A]) Attributes() A {
	return t.attributes
}

func (t TypeReference[A]) FullyQualifiedName() FQName {
	return t.fullyQualified
}

func (t TypeReference[A]) TypeParams() []Type[A] {
	if len(t.typeParams) == 0 {
		return nil
	}
	copied := make([]Type[A], len(t.typeParams))
	copy(copied, t.typeParams)
	return copied
}

// TypeTuple corresponds to: Tuple a (List (Type a))
//
// Represents a tuple type.
type TypeTuple[A any] struct {
	attributes A
	elements   []Type[A]
}

func NewTypeTuple[A any](attributes A, elements []Type[A]) Type[A] {
	var copied []Type[A]
	if len(elements) > 0 {
		copied = make([]Type[A], len(elements))
		copy(copied, elements)
	}
	return TypeTuple[A]{attributes: attributes, elements: copied}
}

func (TypeTuple[A]) isType() {
	// Marker method for the Type sum type.
}

func (t TypeTuple[A]) Attributes() A {
	return t.attributes
}

func (t TypeTuple[A]) Elements() []Type[A] {
	if len(t.elements) == 0 {
		return nil
	}
	copied := make([]Type[A], len(t.elements))
	copy(copied, t.elements)
	return copied
}

// TypeRecord corresponds to: Record a (List (Field a))
//
// Represents a closed record type.
type TypeRecord[A any] struct {
	attributes A
	fields     []Field[A]
}

func NewTypeRecord[A any](attributes A, fields []Field[A]) Type[A] {
	var copied []Field[A]
	if len(fields) > 0 {
		copied = make([]Field[A], len(fields))
		copy(copied, fields)
	}
	return TypeRecord[A]{attributes: attributes, fields: copied}
}

func (TypeRecord[A]) isType() {
	// Marker method for the Type sum type.
}

func (t TypeRecord[A]) Attributes() A {
	return t.attributes
}

func (t TypeRecord[A]) Fields() []Field[A] {
	if len(t.fields) == 0 {
		return nil
	}
	copied := make([]Field[A], len(t.fields))
	copy(copied, t.fields)
	return copied
}

// TypeExtensibleRecord corresponds to: ExtensibleRecord a Name (List (Field a))
//
// Represents an extensible record type where the variable represents the base.
type TypeExtensibleRecord[A any] struct {
	attributes   A
	variableName Name
	fields       []Field[A]
}

func NewTypeExtensibleRecord[A any](attributes A, variableName Name, fields []Field[A]) Type[A] {
	var copied []Field[A]
	if len(fields) > 0 {
		copied = make([]Field[A], len(fields))
		copy(copied, fields)
	}
	return TypeExtensibleRecord[A]{attributes: attributes, variableName: variableName, fields: copied}
}

func (TypeExtensibleRecord[A]) isType() {
	// Marker method for the Type sum type.
}

func (t TypeExtensibleRecord[A]) Attributes() A {
	return t.attributes
}

func (t TypeExtensibleRecord[A]) VariableName() Name {
	return t.variableName
}

func (t TypeExtensibleRecord[A]) Fields() []Field[A] {
	if len(t.fields) == 0 {
		return nil
	}
	copied := make([]Field[A], len(t.fields))
	copy(copied, t.fields)
	return copied
}

// TypeFunction corresponds to: Function a (Type a) (Type a)
//
// Represents a function type.
type TypeFunction[A any] struct {
	attributes A
	argument   Type[A]
	result     Type[A]
}

func NewTypeFunction[A any](attributes A, argument Type[A], result Type[A]) Type[A] {
	return TypeFunction[A]{attributes: attributes, argument: argument, result: result}
}

func (TypeFunction[A]) isType() {
	// Marker method for the Type sum type.
}

func (t TypeFunction[A]) Attributes() A {
	return t.attributes
}

func (t TypeFunction[A]) Argument() Type[A] {
	return t.argument
}

func (t TypeFunction[A]) Result() Type[A] {
	return t.result
}

// TypeUnit corresponds to: Unit a
//
// Represents the unit type.
type TypeUnit[A any] struct {
	attributes A
}

func NewTypeUnit[A any](attributes A) Type[A] {
	return TypeUnit[A]{attributes: attributes}
}

func (TypeUnit[A]) isType() {
	// Marker method for the Type sum type.
}

func (t TypeUnit[A]) Attributes() A {
	return t.attributes
}

// EqualType performs structural equality between two types using the provided
// attribute equality function.
func EqualType[A any](eqAttributes func(A, A) bool, left Type[A], right Type[A]) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}

	return equalTypeConcrete(eqAttributes, left, right)
}

func equalTypeConcrete[A any](eqAttributes func(A, A) bool, left Type[A], right Type[A]) bool {
	switch l := left.(type) {
	case TypeVariable[A]:
		r, ok := right.(TypeVariable[A])
		return ok && eqAttributes(l.attributes, r.attributes) && l.name.Equal(r.name)

	case TypeReference[A]:
		r, ok := right.(TypeReference[A])
		return ok && equalTypeReference(eqAttributes, l, r)

	case TypeTuple[A]:
		r, ok := right.(TypeTuple[A])
		return ok && equalTypeTuple(eqAttributes, l, r)

	case TypeRecord[A]:
		r, ok := right.(TypeRecord[A])
		return ok && equalTypeRecord(eqAttributes, l, r)

	case TypeExtensibleRecord[A]:
		r, ok := right.(TypeExtensibleRecord[A])
		return ok && equalTypeExtensibleRecord(eqAttributes, l, r)

	case TypeFunction[A]:
		r, ok := right.(TypeFunction[A])
		return ok && equalTypeFunction(eqAttributes, l, r)

	case TypeUnit[A]:
		r, ok := right.(TypeUnit[A])
		return ok && eqAttributes(l.attributes, r.attributes)

	default:
		return false
	}
}

func equalTypeReference[A any](eqAttributes func(A, A) bool, left TypeReference[A], right TypeReference[A]) bool {
	if !eqAttributes(left.attributes, right.attributes) {
		return false
	}
	if !left.fullyQualified.Equal(right.fullyQualified) {
		return false
	}
	if len(left.typeParams) != len(right.typeParams) {
		return false
	}
	for i := range left.typeParams {
		if !EqualType(eqAttributes, left.typeParams[i], right.typeParams[i]) {
			return false
		}
	}
	return true
}

func equalTypeTuple[A any](eqAttributes func(A, A) bool, left TypeTuple[A], right TypeTuple[A]) bool {
	if !eqAttributes(left.attributes, right.attributes) {
		return false
	}
	if len(left.elements) != len(right.elements) {
		return false
	}
	for i := range left.elements {
		if !EqualType(eqAttributes, left.elements[i], right.elements[i]) {
			return false
		}
	}
	return true
}

func equalTypeRecord[A any](eqAttributes func(A, A) bool, left TypeRecord[A], right TypeRecord[A]) bool {
	if !eqAttributes(left.attributes, right.attributes) {
		return false
	}
	return equalFields(eqAttributes, left.fields, right.fields)
}

func equalTypeExtensibleRecord[A any](eqAttributes func(A, A) bool, left TypeExtensibleRecord[A], right TypeExtensibleRecord[A]) bool {
	if !eqAttributes(left.attributes, right.attributes) {
		return false
	}
	if !left.variableName.Equal(right.variableName) {
		return false
	}
	return equalFields(eqAttributes, left.fields, right.fields)
}

func equalTypeFunction[A any](eqAttributes func(A, A) bool, left TypeFunction[A], right TypeFunction[A]) bool {
	if !eqAttributes(left.attributes, right.attributes) {
		return false
	}
	if !EqualType(eqAttributes, left.argument, right.argument) {
		return false
	}
	return EqualType(eqAttributes, left.result, right.result)
}

func equalFields[A any](eqAttributes func(A, A) bool, left []Field[A], right []Field[A]) bool {
	if len(left) != len(right) {
		return false
	}
	for i := range left {
		if !left[i].name.Equal(right[i].name) {
			return false
		}
		if !EqualType(eqAttributes, left[i].tpe, right[i].tpe) {
			return false
		}
	}
	return true
}
