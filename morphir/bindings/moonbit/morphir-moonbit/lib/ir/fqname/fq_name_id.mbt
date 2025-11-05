///|
pub fn fq_name(
  package_name : @package.PackageName,
  module_path : @module.ModulePath,
  local_name : @name.Name,
) -> FQName {
  { package_name, module_path, local_name }
}

pub struct FQNameId(Int) derive(Eq, Hash, Show)

pub fn fq_name_id(id : Int) -> FQNameId {
  FQNameId(id)
}
pub fn FQNameId::from_int(id : Int) -> FQNameId {
  FQNameId(id)
}