///|
pub enum Type[A] {
  Variable(A, Name)
  Tuple(A, @list.List[Type[A]])
  Function(A, Type[A], Type[A])
  Unit(A)
} derive(Eq, Hash, Show)

///|
pub fn[A] Type::function(
  attributes : A,
  parameter_type : Type[A],
  return_type : Type[A],
) -> Type[A] {
  Type::Function(attributes, parameter_type, return_type)
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
