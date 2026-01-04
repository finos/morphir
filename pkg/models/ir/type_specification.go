package ir

// TypeSpecification corresponds to Morphir.IR.Type.Specification.
//
// The name is prefixed to avoid collisions with other IR modules (e.g. ModuleSpecification).
type TypeSpecification[A any] interface {
	isTypeSpecification()
	TypeParams() []Name
}

// TypeAliasSpecification corresponds to: TypeAliasSpecification (List Name) (Type a)
type TypeAliasSpecification[A any] struct {
	params []Name
	exp    Type[A]
}

func NewTypeAliasSpecification[A any](params []Name, exp Type[A]) TypeSpecification[A] {
	var copied []Name
	if len(params) > 0 {
		copied = make([]Name, len(params))
		copy(copied, params)
	}
	return TypeAliasSpecification[A]{params: copied, exp: exp}
}

func (TypeAliasSpecification[A]) isTypeSpecification() {
	// Marker method for the TypeSpecification sum type.
}

func (s TypeAliasSpecification[A]) TypeParams() []Name {
	if len(s.params) == 0 {
		return nil
	}
	copied := make([]Name, len(s.params))
	copy(copied, s.params)
	return copied
}

func (s TypeAliasSpecification[A]) Expression() Type[A] {
	return s.exp
}

// OpaqueTypeSpecification corresponds to: OpaqueTypeSpecification (List Name)
type OpaqueTypeSpecification[A any] struct {
	params []Name
}

func NewOpaqueTypeSpecification[A any](params []Name) TypeSpecification[A] {
	var copied []Name
	if len(params) > 0 {
		copied = make([]Name, len(params))
		copy(copied, params)
	}
	return OpaqueTypeSpecification[A]{params: copied}
}

func (OpaqueTypeSpecification[A]) isTypeSpecification() {
	// Marker method for the TypeSpecification sum type.
}

func (s OpaqueTypeSpecification[A]) TypeParams() []Name {
	if len(s.params) == 0 {
		return nil
	}
	copied := make([]Name, len(s.params))
	copy(copied, s.params)
	return copied
}

// CustomTypeSpecification corresponds to: CustomTypeSpecification (List Name) (Constructors a)
type CustomTypeSpecification[A any] struct {
	params       []Name
	constructors TypeConstructors[A]
}

func NewCustomTypeSpecification[A any](params []Name, ctors TypeConstructors[A]) TypeSpecification[A] {
	var copiedParams []Name
	if len(params) > 0 {
		copiedParams = make([]Name, len(params))
		copy(copiedParams, params)
	}
	var copiedCtors TypeConstructors[A]
	if len(ctors) > 0 {
		copiedCtors = make(TypeConstructors[A], len(ctors))
		copy(copiedCtors, ctors)
	}
	return CustomTypeSpecification[A]{params: copiedParams, constructors: copiedCtors}
}

func (CustomTypeSpecification[A]) isTypeSpecification() {
	// Marker method for the TypeSpecification sum type.
}

func (s CustomTypeSpecification[A]) TypeParams() []Name {
	if len(s.params) == 0 {
		return nil
	}
	copied := make([]Name, len(s.params))
	copy(copied, s.params)
	return copied
}

func (s CustomTypeSpecification[A]) Constructors() TypeConstructors[A] {
	if len(s.constructors) == 0 {
		return nil
	}
	copied := make(TypeConstructors[A], len(s.constructors))
	copy(copied, s.constructors)
	return copied
}

// DerivedTypeSpecificationDetails corresponds to:
// { baseType : Type a, fromBaseType : FQName, toBaseType : FQName }
type DerivedTypeSpecificationDetails[A any] struct {
	baseType     Type[A]
	fromBaseType FQName
	toBaseType   FQName
}

func DerivedTypeSpecificationDetailsFromParts[A any](baseType Type[A], fromBaseType FQName, toBaseType FQName) DerivedTypeSpecificationDetails[A] {
	return DerivedTypeSpecificationDetails[A]{
		baseType:     baseType,
		fromBaseType: fromBaseType,
		toBaseType:   toBaseType,
	}
}

func (d DerivedTypeSpecificationDetails[A]) BaseType() Type[A] {
	return d.baseType
}

func (d DerivedTypeSpecificationDetails[A]) FromBaseType() FQName {
	return d.fromBaseType
}

func (d DerivedTypeSpecificationDetails[A]) ToBaseType() FQName {
	return d.toBaseType
}

// DerivedTypeSpecification corresponds to: DerivedTypeSpecification (List Name) DerivedTypeSpecificationDetails
type DerivedTypeSpecification[A any] struct {
	params  []Name
	details DerivedTypeSpecificationDetails[A]
}

func NewDerivedTypeSpecification[A any](params []Name, details DerivedTypeSpecificationDetails[A]) TypeSpecification[A] {
	var copied []Name
	if len(params) > 0 {
		copied = make([]Name, len(params))
		copy(copied, params)
	}
	return DerivedTypeSpecification[A]{params: copied, details: details}
}

func (DerivedTypeSpecification[A]) isTypeSpecification() {
	// Marker method for the TypeSpecification sum type.
}

func (s DerivedTypeSpecification[A]) TypeParams() []Name {
	if len(s.params) == 0 {
		return nil
	}
	copied := make([]Name, len(s.params))
	copy(copied, s.params)
	return copied
}

func (s DerivedTypeSpecification[A]) Details() DerivedTypeSpecificationDetails[A] {
	return s.details
}
