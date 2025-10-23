///|
pub struct ModulePath(@list.List[@name.Name]) derive(Eq, Hash, Show)

///|
pub fn ModulePath::from_list(parts : @list.List[@name.Name]) -> ModulePath {
  ModulePath(parts)
}

///|
pub fn ModulePath::to_list(self : ModulePath) -> @list.List[@name.Name] {
  self.0
}

///|
pub fn ModulePath::to_path(self : ModulePath) -> @path.Path {
  @path.Path::from_list(self.0)
}
