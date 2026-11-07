// Adapted from Morphir.IR.Type in finos/morphir-elm.
// Copyright 2020 Morgan Stanley. Copyright 2026 FINOS.
// SPDX-License-Identifier: Apache-2.0

///|
#derive(Eq, Debug)
pub(all) enum Type[A] {
  Variable(A, Name)
  Reference(A, FQName, Array[Type[A]])
  Tuple(A, Array[Type[A]])
  Record(A, Array[Field[A]])
  ExtensibleRecord(A, Name, Array[Field[A]])
  Function(A, Type[A], Type[A])
  Unit(A)
}

///|
#derive(Eq, Debug)
pub(all) struct Field[A] {
  name : Name
  tpe : Type[A]
}

///|
pub type Constructors[A] = Map[Name, Array[(Name, Type[A])]]

///|
#derive(Eq, Debug)
pub(all) enum TypeSpecification[A] {
  TypeAliasSpecification(Array[Name], Type[A])
  OpaqueTypeSpecification(Array[Name])
  CustomTypeSpecification(Array[Name], Constructors[A])
  DerivedTypeSpecification(Array[Name], DerivedTypeDetails[A])
}

///|
#derive(Eq, Debug)
pub(all) struct DerivedTypeDetails[A] {
  base_type : Type[A]
  from_base_type : FQName
  to_base_type : FQName
}

///|
#derive(Eq, Debug)
pub(all) enum TypeDefinition[A] {
  TypeAliasDefinition(Array[Name], Type[A])
  CustomTypeDefinition(Array[Name], AccessControlled[Constructors[A]])
}

///|
/// Public constructors appear in the specification; private ones become opaque.
pub fn[A] TypeDefinition::to_specification(
  self : TypeDefinition[A],
) -> TypeSpecification[A] {
  match self {
    TypeAliasDefinition(params, body) => TypeAliasSpecification(params, body)
    CustomTypeDefinition(params, constructors) =>
      match constructors.access {
        Public => CustomTypeSpecification(params, constructors.value)
        Private => OpaqueTypeSpecification(params)
      }
  }
}

///|
pub fn[A, B] Type::map_attributes(self : Type[A], f : (A) -> B) -> Type[B] {
  match self {
    Variable(a, n) => Variable(f(a), n)
    Reference(a, n, args) =>
      Reference(f(a), n, args.map(t => t.map_attributes(f)))
    Tuple(a, items) => Tuple(f(a), items.map(t => t.map_attributes(f)))
    Record(a, fields) =>
      Record(
        f(a),
        fields.map(field => {
          name: field.name,
          tpe: field.tpe.map_attributes(f),
        }),
      )
    ExtensibleRecord(a, n, fields) =>
      ExtensibleRecord(
        f(a),
        n,
        fields.map(field => {
          name: field.name,
          tpe: field.tpe.map_attributes(f),
        }),
      )
    Function(a, parameter, result) =>
      Function(f(a), parameter.map_attributes(f), result.map_attributes(f))
    Unit(a) => Unit(f(a))
  }
}
