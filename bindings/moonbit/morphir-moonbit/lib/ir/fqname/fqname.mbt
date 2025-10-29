///|
pub struct FQName{ 
  package_name: @package.PackageName
  module_path: @module.ModulePath
  local_name: @name.Name
} derive (
  Eq,
  Hash,
  Show,
)