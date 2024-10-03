package org.finos.morphir.ir.gen1

/** A package name is a globally unique identifier for a package. It is represented by a `Path` which is a list of
  * names.
  */
sealed case class PackageName(path: Path) { self =>
  def ++(that: PackageName): PackageName = PackageName(path ++ that.path)
  def ++(that: Path): PackageName        = PackageName(path ++ that)
  def /(pathString: String): PackageName = PackageName(path ++ Path.fromString(pathString))

  @deprecated("Use `%(moduleName: ModuleName)` instead", "0.4.0-M3")
  def /(moduleName: ModuleName): QualifiedModuleName = QualifiedModuleName(self, moduleName)
  def %(modulePath: String): QualifiedModuleName     = QualifiedModuleName(self, ModuleName.fromString(modulePath))
  def %(moduleName: ModuleName): QualifiedModuleName = QualifiedModuleName(self, moduleName)

  @inline def isEmpty: Boolean = path.isEmpty
  @inline def toPath: Path     = path

  def render(implicit renderer: PathRenderer): String = renderer(path)
  /// An alias for `render`
  def show(implicit renderer: PathRenderer): String = render
  override def toString(): String                   = render
}

val root = PackageName.root

object PackageName {
  val empty: PackageName = PackageName(Path.empty)
  val root: PackageName  = PackageName(Path.empty)

  // val morphirSdk:PackageName = PackageName.fromString("Morphir.SDK")

  def fromPath(path: Path): PackageName = PackageName(path)

  def fromString(str: String): PackageName = PackageName(Path.fromString(str))
  def fromIterable(segments: Iterable[Name]): PackageName =
    PackageName(Path.fromIterable(segments))
  def fromList(segments: List[Name]): PackageName =
    PackageName(Path.fromList(segments))

}
