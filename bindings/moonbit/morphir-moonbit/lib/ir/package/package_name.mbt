///|
pub struct PackageName(@list.List[@name.Name]) derive(Eq, Hash, Show)

///|
pub fn PackageName::from_list(parts : @list.List[@name.Name]) -> PackageName {
  PackageName(parts)
}

///|
pub fn PackageName::to_list(self : PackageName) -> @list.List[@name.Name] {
  self.0
}

///|
pub fn PackageName::to_path(self : PackageName) -> @path.Path {
  @path.Path::from_list(self.0)
}
