package morphir.cdk

case class Name(runs: List[String])
object Name:
  def apply(name: String): Name = Name(List(name))
  given IntoName[Name] with
    extension (self: Name) def intoName: Name = self

case class Path(toList: List[Name])
object Path {
  given IntoPath[Path] with
    extension (self: Path) def intoPath: Path = self
}

case class PackageName(path: Path)
object PackageName {
  given IntoPath[PackageName] with
    extension (self: PackageName) def intoPath: Path = self.path
}

case class ModuleName(path: Path)
object ModuleName {
  given IntoPath[ModuleName] with
    extension (self: ModuleName) def intoPath: Path = self.path
}

case class FQName(
    packagePath: PackageName,
    modulePath: ModuleName,
    localName: Name
)

object FQName:
  given IntoFQName[FQName] with
    extension (self: FQName) def intoFQName: FQName = self
