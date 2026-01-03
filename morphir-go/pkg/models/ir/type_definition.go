package ir

// TypeDefinition corresponds to Morphir.IR.Type.Definition.
//
// The name is prefixed to avoid collisions with other IR modules.
type TypeDefinition[A any] interface {
	isTypeDefinition()
	TypeParams() []Name
}

// TypeAliasDefinition corresponds to: TypeAliasDefinition (List Name) (Type a)
type TypeAliasDefinition[A any] struct {
	params []Name
	exp    Type[A]
}

func NewTypeAliasDefinition[A any](params []Name, exp Type[A]) TypeDefinition[A] {
	var copied []Name
	if len(params) > 0 {
		copied = make([]Name, len(params))
		copy(copied, params)
	}
	return TypeAliasDefinition[A]{params: copied, exp: exp}
}

func (TypeAliasDefinition[A]) isTypeDefinition() {
	// Marker method for the TypeDefinition sum type.
}

func (d TypeAliasDefinition[A]) TypeParams() []Name {
	if len(d.params) == 0 {
		return nil
	}
	copied := make([]Name, len(d.params))
	copy(copied, d.params)
	return copied
}

func (d TypeAliasDefinition[A]) Expression() Type[A] {
	return d.exp
}

// CustomTypeDefinition corresponds to:
// CustomTypeDefinition (List Name) (AccessControlled (Constructors a))
type CustomTypeDefinition[A any] struct {
	params       []Name
	constructors AccessControlled[TypeConstructors[A]]
}

func NewCustomTypeDefinition[A any](params []Name, ctors AccessControlled[TypeConstructors[A]]) TypeDefinition[A] {
	var copied []Name
	if len(params) > 0 {
		copied = make([]Name, len(params))
		copy(copied, params)
	}
	return CustomTypeDefinition[A]{params: copied, constructors: ctors}
}

func (CustomTypeDefinition[A]) isTypeDefinition() {
	// Marker method for the TypeDefinition sum type.
}

func (d CustomTypeDefinition[A]) TypeParams() []Name {
	if len(d.params) == 0 {
		return nil
	}
	copied := make([]Name, len(d.params))
	copy(copied, d.params)
	return copied
}

func (d CustomTypeDefinition[A]) Constructors() AccessControlled[TypeConstructors[A]] {
	return d.constructors
}
