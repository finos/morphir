package ir

// TypeConstructorArg corresponds to (Name, Type a) in Morphir IR.
type TypeConstructorArg[A any] struct {
	name Name
	tpe  Type[A]
}

func TypeConstructorArgFromParts[A any](name Name, tpe Type[A]) TypeConstructorArg[A] {
	return TypeConstructorArg[A]{name: name, tpe: tpe}
}

func (a TypeConstructorArg[A]) Name() Name {
	return a.name
}

func (a TypeConstructorArg[A]) Type() Type[A] {
	return a.tpe
}

// TypeConstructorArgs corresponds to ConstructorArgs a in Morphir IR.
//
// In Elm this is a list of (argName, argType) pairs.
type TypeConstructorArgs[A any] []TypeConstructorArg[A]

// TypeConstructor corresponds to a constructor entry in Constructors a.
type TypeConstructor[A any] struct {
	name Name
	args TypeConstructorArgs[A]
}

func TypeConstructorFromParts[A any](name Name, args TypeConstructorArgs[A]) TypeConstructor[A] {
	var copied TypeConstructorArgs[A]
	if len(args) > 0 {
		copied = make(TypeConstructorArgs[A], len(args))
		copy(copied, args)
	}
	return TypeConstructor[A]{name: name, args: copied}
}

func (c TypeConstructor[A]) Name() Name {
	return c.name
}

func (c TypeConstructor[A]) Args() TypeConstructorArgs[A] {
	if len(c.args) == 0 {
		return nil
	}
	copied := make(TypeConstructorArgs[A], len(c.args))
	copy(copied, c.args)
	return copied
}

// TypeConstructors corresponds to Constructors a in Morphir IR.
//
// In Elm this is Dict Name (ConstructorArgs a), but JSON encoding uses Dict.toList.
// We model it as a list of constructors to keep keys (Name) as a first-class value
// without requiring a comparable map key.
type TypeConstructors[A any] []TypeConstructor[A]
