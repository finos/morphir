package ir

import (
	"errors"
	"fmt"
)

var errTypeMustNotBeNil = errors.New("ir: Type must not be nil")

const errUnsupportedTypeVariantF = "ir: unsupported Type variant %T"

// TypeCases defines handlers for each variant of the Type sum type.
//
// This is a lightweight, non-codegen alternative to DU pattern matching.
// It is intended to reduce repetitive type-switch logic at call sites.
//
// If a handler is nil for the encountered case, MatchType returns an error.
// For a panic-on-missing-handler variant, use MustMatchType.
//
// Note: This helper does not provide compile-time exhaustiveness, but it
// concentrates case handling in one place and makes it easy to grep.
type TypeCases[A any, R any] struct {
	Variable         func(TypeVariable[A]) R
	Reference        func(TypeReference[A]) R
	Tuple            func(TypeTuple[A]) R
	Record           func(TypeRecord[A]) R
	ExtensibleRecord func(TypeExtensibleRecord[A]) R
	Function         func(TypeFunction[A]) R
	Unit             func(TypeUnit[A]) R
}

// MatchType pattern-matches on Type and invokes the corresponding handler.
func MatchType[A any, R any](t Type[A], c TypeCases[A, R]) (R, error) {
	var zero R
	if t == nil {
		return zero, errTypeMustNotBeNil
	}

	switch v := t.(type) {
	case TypeVariable[A]:
		return matchTypeVariable(c, v)
	case TypeReference[A]:
		return matchTypeReference(c, v)
	case TypeTuple[A]:
		return matchTypeTuple(c, v)
	case TypeRecord[A]:
		return matchTypeRecord(c, v)
	case TypeExtensibleRecord[A]:
		return matchTypeExtensibleRecord(c, v)
	case TypeFunction[A]:
		return matchTypeFunction(c, v)
	case TypeUnit[A]:
		return matchTypeUnit(c, v)
	default:
		return zero, fmt.Errorf(errUnsupportedTypeVariantF, t)
	}
}

func matchTypeVariable[A any, R any](c TypeCases[A, R], v TypeVariable[A]) (R, error) {
	var zero R
	if c.Variable == nil {
		return zero, fmt.Errorf("ir: missing handler for TypeVariable")
	}
	return c.Variable(v), nil
}

func matchTypeReference[A any, R any](c TypeCases[A, R], v TypeReference[A]) (R, error) {
	var zero R
	if c.Reference == nil {
		return zero, fmt.Errorf("ir: missing handler for TypeReference")
	}
	return c.Reference(v), nil
}

func matchTypeTuple[A any, R any](c TypeCases[A, R], v TypeTuple[A]) (R, error) {
	var zero R
	if c.Tuple == nil {
		return zero, fmt.Errorf("ir: missing handler for TypeTuple")
	}
	return c.Tuple(v), nil
}

func matchTypeRecord[A any, R any](c TypeCases[A, R], v TypeRecord[A]) (R, error) {
	var zero R
	if c.Record == nil {
		return zero, fmt.Errorf("ir: missing handler for TypeRecord")
	}
	return c.Record(v), nil
}

func matchTypeExtensibleRecord[A any, R any](c TypeCases[A, R], v TypeExtensibleRecord[A]) (R, error) {
	var zero R
	if c.ExtensibleRecord == nil {
		return zero, fmt.Errorf("ir: missing handler for TypeExtensibleRecord")
	}
	return c.ExtensibleRecord(v), nil
}

func matchTypeFunction[A any, R any](c TypeCases[A, R], v TypeFunction[A]) (R, error) {
	var zero R
	if c.Function == nil {
		return zero, fmt.Errorf("ir: missing handler for TypeFunction")
	}
	return c.Function(v), nil
}

func matchTypeUnit[A any, R any](c TypeCases[A, R], v TypeUnit[A]) (R, error) {
	var zero R
	if c.Unit == nil {
		return zero, fmt.Errorf("ir: missing handler for TypeUnit")
	}
	return c.Unit(v), nil
}

// MustMatchType is like MatchType but panics on error.
func MustMatchType[A any, R any](t Type[A], c TypeCases[A, R]) R {
	result, err := MatchType[A](t, c)
	if err != nil {
		panic(err)
	}
	return result
}

// FoldedField is a record field value whose Type has already been folded.
//
// This mirrors Field[A] but carries the folded result instead of Type[A].
//
// It uses unexported fields + accessors to keep the functional/immutable style.
type FoldedField[R any] struct {
	name Name
	tpe  R
}

func newFoldedField[R any](name Name, tpe R) FoldedField[R] {
	return FoldedField[R]{name: name, tpe: tpe}
}

func (f FoldedField[R]) Name() Name {
	return f.name
}

func (f FoldedField[R]) Type() R {
	return f.tpe
}

// TypeFold is an algebra for folding a Type tree into a result R.
//
// The fold is post-order: each handler receives already-folded child results.
// If a handler is nil for the encountered case, FoldType returns an error.
type TypeFold[A any, R any] struct {
	Variable         func(attributes A, name Name) R
	Reference        func(attributes A, fullyQualified FQName, typeParams []R) R
	Tuple            func(attributes A, elements []R) R
	Record           func(attributes A, fields []FoldedField[R]) R
	ExtensibleRecord func(attributes A, variableName Name, fields []FoldedField[R]) R
	Function         func(attributes A, argument R, result R) R
	Unit             func(attributes A) R
}

// MapType performs a bottom-up rewrite of a Type tree.
//
// Children are mapped first, then the node is rebuilt, then rewrite (if non-nil)
// is applied to the rebuilt node.
//
// This is useful for implementing normalization or transformation passes while
// keeping IR values immutable.
func MapType[A any](t Type[A], rewrite func(Type[A]) (Type[A], error)) (Type[A], error) {
	if t == nil {
		return nil, errTypeMustNotBeNil
	}

	switch v := t.(type) {
	case TypeVariable[A]:
		node, err := mapTypeVariable(v)
		return mapTypeThenRewrite(rewrite, node, err)
	case TypeReference[A]:
		node, err := mapTypeReference(v)
		return mapTypeThenRewrite(rewrite, node, err)
	case TypeTuple[A]:
		node, err := mapTypeTuple(v, rewrite)
		return mapTypeThenRewrite(rewrite, node, err)
	case TypeRecord[A]:
		node, err := mapTypeRecord(v, rewrite)
		return mapTypeThenRewrite(rewrite, node, err)
	case TypeExtensibleRecord[A]:
		node, err := mapTypeExtensibleRecord(v, rewrite)
		return mapTypeThenRewrite(rewrite, node, err)
	case TypeFunction[A]:
		node, err := mapTypeFunction(v, rewrite)
		return mapTypeThenRewrite(rewrite, node, err)
	case TypeUnit[A]:
		node, err := mapTypeUnit(v)
		return mapTypeThenRewrite(rewrite, node, err)
	default:
		return nil, fmt.Errorf(errUnsupportedTypeVariantF, t)
	}
}

// MustMapType is like MapType but panics on error.
func MustMapType[A any](t Type[A], rewrite func(Type[A]) (Type[A], error)) Type[A] {
	result, err := MapType[A](t, rewrite)
	if err != nil {
		panic(err)
	}
	return result
}

// MapTypeAttributes maps the attribute type at each node while preserving the
// Type tree structure.
func MapTypeAttributes[A any, B any](t Type[A], mapAttributes func(A) B) (Type[B], error) {
	if t == nil {
		return nil, errTypeMustNotBeNil
	}
	if mapAttributes == nil {
		return nil, fmt.Errorf("ir: mapAttributes must not be nil")
	}

	switch v := t.(type) {
	case TypeVariable[A]:
		return NewTypeVariable[B](mapAttributes(v.attributes), v.name), nil
	case TypeReference[A]:
		params, err := mapTypeAttributesList[A, B](v.typeParams, mapAttributes)
		if err != nil {
			return nil, err
		}
		return NewTypeReference[B](mapAttributes(v.attributes), v.fullyQualified, params), nil
	case TypeTuple[A]:
		elems, err := mapTypeAttributesList[A, B](v.elements, mapAttributes)
		if err != nil {
			return nil, err
		}
		return NewTypeTuple[B](mapAttributes(v.attributes), elems), nil
	case TypeRecord[A]:
		fields, err := mapTypeAttributesFields[A, B](v.fields, mapAttributes)
		if err != nil {
			return nil, err
		}
		return NewTypeRecord[B](mapAttributes(v.attributes), fields), nil
	case TypeExtensibleRecord[A]:
		fields, err := mapTypeAttributesFields[A, B](v.fields, mapAttributes)
		if err != nil {
			return nil, err
		}
		return NewTypeExtensibleRecord[B](mapAttributes(v.attributes), v.variableName, fields), nil
	case TypeFunction[A]:
		arg, err := MapTypeAttributes[A, B](v.argument, mapAttributes)
		if err != nil {
			return nil, err
		}
		res, err := MapTypeAttributes[A, B](v.result, mapAttributes)
		if err != nil {
			return nil, err
		}
		return NewTypeFunction[B](mapAttributes(v.attributes), arg, res), nil
	case TypeUnit[A]:
		return NewTypeUnit[B](mapAttributes(v.attributes)), nil
	default:
		return nil, fmt.Errorf(errUnsupportedTypeVariantF, t)
	}
}

// MustMapTypeAttributes is like MapTypeAttributes but panics on error.
func MustMapTypeAttributes[A any, B any](t Type[A], mapAttributes func(A) B) Type[B] {
	result, err := MapTypeAttributes[A, B](t, mapAttributes)
	if err != nil {
		panic(err)
	}
	return result
}

// FoldType reduces a Type tree into a single value using the provided algebra.
func FoldType[A any, R any](t Type[A], f TypeFold[A, R]) (R, error) {
	var zero R
	if t == nil {
		return zero, errTypeMustNotBeNil
	}

	switch v := t.(type) {
	case TypeVariable[A]:
		return foldTypeVariable(f, v)
	case TypeReference[A]:
		return foldTypeReference(f, v)
	case TypeTuple[A]:
		return foldTypeTuple(f, v)
	case TypeRecord[A]:
		return foldTypeRecord(f, v)
	case TypeExtensibleRecord[A]:
		return foldTypeExtensibleRecord(f, v)
	case TypeFunction[A]:
		return foldTypeFunction(f, v)
	case TypeUnit[A]:
		return foldTypeUnit(f, v)
	default:
		return zero, fmt.Errorf(errUnsupportedTypeVariantF, t)
	}
}

func foldTypeVariable[A any, R any](f TypeFold[A, R], v TypeVariable[A]) (R, error) {
	var zero R
	if f.Variable == nil {
		return zero, fmt.Errorf("ir: missing fold handler for TypeVariable")
	}
	return f.Variable(v.attributes, v.name), nil
}

func foldTypeReference[A any, R any](f TypeFold[A, R], v TypeReference[A]) (R, error) {
	var zero R
	if f.Reference == nil {
		return zero, fmt.Errorf("ir: missing fold handler for TypeReference")
	}
	params, err := foldTypeList[A](v.typeParams, f)
	if err != nil {
		return zero, err
	}
	return f.Reference(v.attributes, v.fullyQualified, params), nil
}

func foldTypeTuple[A any, R any](f TypeFold[A, R], v TypeTuple[A]) (R, error) {
	var zero R
	if f.Tuple == nil {
		return zero, fmt.Errorf("ir: missing fold handler for TypeTuple")
	}
	elems, err := foldTypeList[A](v.elements, f)
	if err != nil {
		return zero, err
	}
	return f.Tuple(v.attributes, elems), nil
}

func foldTypeRecord[A any, R any](f TypeFold[A, R], v TypeRecord[A]) (R, error) {
	var zero R
	if f.Record == nil {
		return zero, fmt.Errorf("ir: missing fold handler for TypeRecord")
	}
	fields, err := foldFields[A](v.fields, f)
	if err != nil {
		return zero, err
	}
	return f.Record(v.attributes, fields), nil
}

func foldTypeExtensibleRecord[A any, R any](f TypeFold[A, R], v TypeExtensibleRecord[A]) (R, error) {
	var zero R
	if f.ExtensibleRecord == nil {
		return zero, fmt.Errorf("ir: missing fold handler for TypeExtensibleRecord")
	}
	fields, err := foldFields[A](v.fields, f)
	if err != nil {
		return zero, err
	}
	return f.ExtensibleRecord(v.attributes, v.variableName, fields), nil
}

func foldTypeFunction[A any, R any](f TypeFold[A, R], v TypeFunction[A]) (R, error) {
	var zero R
	if f.Function == nil {
		return zero, fmt.Errorf("ir: missing fold handler for TypeFunction")
	}
	arg, err := FoldType[A](v.argument, f)
	if err != nil {
		return zero, err
	}
	res, err := FoldType[A](v.result, f)
	if err != nil {
		return zero, err
	}
	return f.Function(v.attributes, arg, res), nil
}

func foldTypeUnit[A any, R any](f TypeFold[A, R], v TypeUnit[A]) (R, error) {
	var zero R
	if f.Unit == nil {
		return zero, fmt.Errorf("ir: missing fold handler for TypeUnit")
	}
	return f.Unit(v.attributes), nil
}

func foldTypeList[A any, R any](items []Type[A], f TypeFold[A, R]) ([]R, error) {
	var zero []R
	if len(items) == 0 {
		return nil, nil
	}

	result := make([]R, 0, len(items))
	for _, item := range items {
		folded, err := FoldType[A](item, f)
		if err != nil {
			return zero, err
		}
		result = append(result, folded)
	}
	return result, nil
}

func foldFields[A any, R any](fields []Field[A], f TypeFold[A, R]) ([]FoldedField[R], error) {
	var zero []FoldedField[R]
	if len(fields) == 0 {
		return nil, nil
	}

	result := make([]FoldedField[R], 0, len(fields))
	for _, field := range fields {
		folded, err := FoldType[A](field.tpe, f)
		if err != nil {
			return zero, err
		}
		result = append(result, newFoldedField(field.name, folded))
	}
	return result, nil
}

func mapTypeApplyRewrite[A any](node Type[A], rewrite func(Type[A]) (Type[A], error)) (Type[A], error) {
	if rewrite == nil {
		return node, nil
	}
	return rewrite(node)
}

func mapTypeThenRewrite[A any](rewrite func(Type[A]) (Type[A], error), node Type[A], err error) (Type[A], error) {
	if err != nil {
		return nil, err
	}
	return mapTypeApplyRewrite[A](node, rewrite)
}

func mapTypeVariable[A any](v TypeVariable[A]) (Type[A], error) {
	return NewTypeVariable[A](v.attributes, v.name), nil
}

func mapTypeReference[A any](v TypeReference[A]) (Type[A], error) {
	return NewTypeReference[A](v.attributes, v.fullyQualified, v.typeParams), nil
}

func mapTypeTuple[A any](v TypeTuple[A], rewrite func(Type[A]) (Type[A], error)) (Type[A], error) {
	elems, err := mapTypeList[A](v.elements, rewrite)
	if err != nil {
		return nil, err
	}
	return NewTypeTuple[A](v.attributes, elems), nil
}

func mapTypeRecord[A any](v TypeRecord[A], rewrite func(Type[A]) (Type[A], error)) (Type[A], error) {
	fields, err := mapFields[A](v.fields, rewrite)
	if err != nil {
		return nil, err
	}
	return NewTypeRecord[A](v.attributes, fields), nil
}

func mapTypeExtensibleRecord[A any](v TypeExtensibleRecord[A], rewrite func(Type[A]) (Type[A], error)) (Type[A], error) {
	fields, err := mapFields[A](v.fields, rewrite)
	if err != nil {
		return nil, err
	}
	return NewTypeExtensibleRecord[A](v.attributes, v.variableName, fields), nil
}

func mapTypeFunction[A any](v TypeFunction[A], rewrite func(Type[A]) (Type[A], error)) (Type[A], error) {
	arg, err := MapType[A](v.argument, rewrite)
	if err != nil {
		return nil, err
	}
	res, err := MapType[A](v.result, rewrite)
	if err != nil {
		return nil, err
	}
	return NewTypeFunction[A](v.attributes, arg, res), nil
}

func mapTypeUnit[A any](v TypeUnit[A]) (Type[A], error) {
	return NewTypeUnit[A](v.attributes), nil
}

func mapTypeList[A any](items []Type[A], rewrite func(Type[A]) (Type[A], error)) ([]Type[A], error) {
	if len(items) == 0 {
		return nil, nil
	}
	result := make([]Type[A], 0, len(items))
	for _, item := range items {
		mapped, err := MapType[A](item, rewrite)
		if err != nil {
			return nil, err
		}
		result = append(result, mapped)
	}
	return result, nil
}

func mapFields[A any](fields []Field[A], rewrite func(Type[A]) (Type[A], error)) ([]Field[A], error) {
	if len(fields) == 0 {
		return nil, nil
	}
	result := make([]Field[A], 0, len(fields))
	for _, field := range fields {
		mapped, err := MapType[A](field.tpe, rewrite)
		if err != nil {
			return nil, err
		}
		result = append(result, FieldFromParts[A](field.name, mapped))
	}
	return result, nil
}

func mapTypeAttributesList[A any, B any](items []Type[A], mapAttributes func(A) B) ([]Type[B], error) {
	if len(items) == 0 {
		return nil, nil
	}
	result := make([]Type[B], 0, len(items))
	for _, item := range items {
		mapped, err := MapTypeAttributes[A, B](item, mapAttributes)
		if err != nil {
			return nil, err
		}
		result = append(result, mapped)
	}
	return result, nil
}

func mapTypeAttributesFields[A any, B any](fields []Field[A], mapAttributes func(A) B) ([]Field[B], error) {
	if len(fields) == 0 {
		return nil, nil
	}
	result := make([]Field[B], 0, len(fields))
	for _, field := range fields {
		mapped, err := MapTypeAttributes[A, B](field.tpe, mapAttributes)
		if err != nil {
			return nil, err
		}
		result = append(result, FieldFromParts[B](field.name, mapped))
	}
	return result, nil
}

// MustFoldType is like FoldType but panics on error.
func MustFoldType[A any, R any](t Type[A], f TypeFold[A, R]) R {
	result, err := FoldType[A](t, f)
	if err != nil {
		panic(err)
	}
	return result
}
