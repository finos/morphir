///|
pub struct ModulePath(@list.List[@name.Name]) derive(Eq, Hash, Show)

///|
pub fn ModulePath::from_list(parts : @list.List[@name.Name]) -> ModulePath {
  ModulePath(parts)
}

///|
pub fn ModulePath::from_string(name : String) -> ModulePath {
  let path = @path.from_string(name)
  ModulePath(path.to_list())
}

///|
pub fn ModulePath::to_list(self : ModulePath) -> @list.List[@name.Name] {
  self.0
}

pub fn ModulePath::to_string(
  self : ModulePath,
  renderer : @name.NameRenderer,
  separator : String,
) -> String {
  self.0.iter().map(renderer).join(separator)
}

///|
pub fn ModulePath::to_path(self : ModulePath) -> @path.Path {
  @path.Path::from_list(self.0)
}
