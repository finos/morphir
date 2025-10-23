pub struct FQName(@package.PackageName, @module.ModulePath, @name.Name) derive(Eq, Hash, Show)

pub fn fq_name(package_name:@package.PackageName, module_path: @module.ModulePath, local_name: @name.Name) -> FQName {
    FQName(package_name, module_path, local_name)
}