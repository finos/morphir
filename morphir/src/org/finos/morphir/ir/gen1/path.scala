package org.finos.morphir.ir.gen1

import scala.annotation.tailrec

sealed case class Path(segments: Vector[Name]) {
  self =>

  def ++(that: Path): Path = Path(segments ++ that.segments)
//  def ::(name: Name): QName = QName(self.toPath, name)

  /** Indicates whether this path is empty. */
  def isEmpty: Boolean = toList.isEmpty

  def toList: List[Name] = segments.toList

  /** Constructs a new path by combining this path with the given name. */
  def /(name: Name): Path = Path(segments ++ List(name))

  /** Constructs a new path by combining this path with the given path. */
  def /(that: Path): Path = Path(segments ++ that.toList)
  // def %(other: Path): PackageAndModulePath =
  //   PackageAndModulePath(PackageName(self), ModulePath(other))

  def zip(other: Path): (Path, Path) = (self, other)

  def toString(f: Name => String, separator: String): String =
    toList.map(f).mkString(separator)

  /** Checks if this path is a prefix of provided path */
  def isPrefixOf(path: Path): Boolean = Path.isPrefixOf(self, path)

  def parts(implicit renderer: PathRenderer): IndexedSeq[String] = segments.map(_.render(renderer.nameRenderer))

  def render(implicit renderer: PathRenderer): String = renderer(self)
  def render(separator: String)(implicit nameRenderer: NameRenderer): String =
    render(PathRenderer(separator, nameRenderer))

  // def toPackageName(implicit renderer: Name.Renderer = Name.Renderer.TitleCase): PackageName = {
  //   val nsSegments = PackageName.segments(segments.map(_.render))
  //   PackageName.fromIterable(nsSegments)
  // }

  // def toNamespace(implicit renderer: Name.Renderer = Name.Renderer.TitleCase): Namespace = {
  //   val nsSegments = Namespace.segments(segments.map(_.render))
  //   Namespace.fromIterable(nsSegments)
  // }

  override def toString(): String = render
}

object Path {
  val separatorRegex = """[^\w\s]+""".r
  val empty: Path    = Path(Vector.empty)
  val root: Path     = Path(Vector.empty)

  def apply(first: String, rest: String*): Path =
    if (rest.isEmpty) Path(Vector(Name.fromString(first)))
    else Path.fromIterable(Name.fromString(first) +: rest.map(Name.fromString(_)))

  def apply(first: Name, rest: Name*): Path =
    if (rest.isEmpty) Path(Vector(first))
    else Path(first +: rest.toVector)

  /** Translates a string into a path by splitting it into names along special characters. The algorithm will treat any
    * non-word characters that are not spaces as a path separator.
    */
  def fromString(str: String): Path =
    fromArray(separatorRegex.split(str).map(Name.fromString))

  def toString(f: Name => String, separator: String, path: Path): String =
    path.toString(f, separator)

  /// Converts an array of names into a path.
  @inline def fromArray(names: Array[Name]): Path = Path(names.toVector)
  /// Converts names into a path.
  @inline def fromIterable(names: Iterable[Name]): Path = Path(names.toVector)
  /// Converts a list of names into a path.
  @inline def fromList(names: List[Name]): Path = Path(names.toVector)
  /// Converts a list of names into a path.
  @inline def fromList(names: Name*): Path = Path(names.toVector)

  def fromStrings(names: String*): Path = Path(names.map(Name.fromString).toVector)
  /// Converts names into a path.
  @inline def fromVector(names: Vector[Name]): Path = Path(names)

  @inline def toList(path: Path): List[Name] = path.toList.toList

  /** Checks if the first provided path is a prefix of the second path */
  @tailrec
  def isPrefixOf(prefix: Path, path: Path): Boolean = (prefix.toList, path.toList) match {
    case (Nil, _) => true
    case (_, Nil) => false
    case (prefixHead :: prefixTail, pathHead :: pathTail) =>
      if (prefixHead == pathHead)
        isPrefixOf(
          Path.fromList(prefixTail),
          Path.fromList(pathTail)
        )
      else false
  }

  private[morphir] def unsafeMake(parts: Name*): Path = Path(parts.toVector)
}

sealed case class PathRenderer(separator: String, nameRenderer: NameRenderer) extends (Path => String) {
  def apply(path: Path): String        = path.toString(nameRenderer, separator)
  final def render(path: Path): String = apply(path)
}

object PathRenderer {
  val CamelCase: PathRenderer = PathRenderer(".", NameRenderer.CamelCase)
  val KebabCase: PathRenderer = PathRenderer(".", NameRenderer.KebabCase)
  val SnakeCase: PathRenderer = PathRenderer(".", NameRenderer.SnakeCase)
  val TitleCase: PathRenderer = PathRenderer(".", NameRenderer.TitleCase)

  implicit val default: PathRenderer = TitleCase
}
