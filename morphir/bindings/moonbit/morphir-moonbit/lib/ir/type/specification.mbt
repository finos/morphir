///|
pub enum TypeSpecification[A] {
  TypeAliasSpecification(@list.List[Name], Type[A])
  OpaqueTypeSpecification(@list.List[Name])
  CustomTypeSpecification(@list.List[Name], Constructors[A])
  DerivedTypeSpecification(@list.List[Name], DerivedTypeSpecificationDetails[A])
}

///|
pub struct DerivedTypeSpecificationDetails[A] {
  base_type : Type[A]
  from_base_type : @fqname.FQName
  to_base_type : @fqname.FQName
} derive(Eq, Hash, Show)

///|
pub typealias @hashmap.HashMap[Name, ConstructorArgs[A]] as Constructors[A]

///|
pub typealias @list.List[(Name, Type[A])] as ConstructorArgs[A]

///|
pub fn[A] type_alias_specification(
  type_params : @list.List[Name],
  type_expr : Type[A],
) -> TypeSpecification[A] {
  TypeAliasSpecification(type_params, type_expr)
}

///|
pub fn[A] opaque_type_specification(
  type_params : @list.List[Name],
) -> TypeSpecification[A] {
  OpaqueTypeSpecification(type_params)
}

///|
pub fn[A] custom_type_specification(
  type_params : @list.List[Name],
  ctors : Constructors[A],
) -> TypeSpecification[A] {
  CustomTypeSpecification(type_params, ctors)
}

///|
pub fn[A] derived_type_specification(
  type_params : @list.List[Name],
  details : DerivedTypeSpecificationDetails[A],
) -> TypeSpecification[A] {
  DerivedTypeSpecification(type_params, details)
}

///|
pub fn[A] derived_type_specification_details(
  base_type : Type[A],
  from_base_type : @fqname.FQName,
  to_base_type : @fqname.FQName,
) -> DerivedTypeSpecificationDetails[A] {
  { base_type, from_base_type, to_base_type }
}
