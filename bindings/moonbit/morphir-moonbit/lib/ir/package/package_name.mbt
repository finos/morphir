///|
pub struct PackageName(@list.List[@name.Name]) derive(Eq, Hash, Show)

///|
pub fn PackageName::from_list(parts : @list.List[@name.Name]) -> PackageName {
  PackageName(parts)
}

///|
pub fn PackageName::from_string(name : String) -> PackageName {
  let path = @path.from_string(name)
  PackageName(path.to_list())
}

///|
pub fn PackageName::to_list(self : PackageName) -> @list.List[@name.Name] {
  self.0
}

pub fn PackageName::to_string(
  self : PackageName,
  renderer : @name.NameRenderer,
  separator : String,
) -> String {
  self.0.iter().map(renderer).join(separator)
}

///|
pub fn PackageName::to_path(self : PackageName) -> @path.Path {
  @path.Path::from_list(self.0)
}
