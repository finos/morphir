///|
pub enum Type[A] {
  Variable(A, Name)
  Reference(A, @fqname.FQName, @list.List[Type[A]])
  Tuple(A, @list.List[Type[A]])
  Record(A, @list.List[Field[A]])
  ExtensibleRecord(A, Name, @list.List[Field[A]])
  Function(A, Type[A], Type[A])
  Unit(A)
} derive(Eq, Hash, Show)

///|
pub fn[A] Type::extensible_record(
  attributes : A,
  name : Name,
  fields : @list.List[Field[A]],
) -> Type[A] {
  Type::ExtensibleRecord(attributes, name, fields)
}

///|
pub fn[A] Type::function(
  attributes : A,
  parameter_type : Type[A],
  return_type : Type[A],
) -> Type[A] {
  Type::Function(attributes, parameter_type, return_type)
}

///|
pub fn[A] Type::record(
  attributes : A,
  fields : @list.List[Field[A]],
) -> Type[A] {
  Type::Record(attributes, fields)
}

///|
pub fn[A] Type::reference(
  attributes : A,
  fq_name : @fqname.FQName,
  type_args : @list.List[Type[A]],
) -> Type[A] {
  Type::Reference(attributes, fq_name, type_args)
}

///|
pub fn[A] Type::tuple(
  attributes : A,
  element_types : @list.List[Type[A]],
) -> Type[A] {
  Type::Tuple(attributes, element_types)
}

///|
pub fn[A] Type::unit(attributes : A) -> Type[A] {
  Type::Unit(attributes)
}

///|
pub fn[A] Type::variable(attributes : A, name : Name) -> Type[A] {
  Type::Variable(attributes, name)
}

pub fn[A] Type::attributes(self : Type[A]) -> A {
  match self {
    Variable(attributes, _) => attributes
    Reference(attributes, _, _) => attributes
    Tuple(attributes, _) => attributes
    Record(attributes, _) => attributes
    ExtensibleRecord(attributes, _, _) => attributes
    Function(attributes, _, _) => attributes
    Unit(attributes) => attributes
  }
}