package org.finos.morphir.ir.gen1

trait NamespaceModule { self: NameModule with PathModule with ModuleNameModule =>
  sealed case class Namespace(path: Path) { self =>
    def ++(name: Namespace): Namespace        = Namespace(path ++ path)
    def /(segment: String): Namespace         = Namespace(path ++ Path.fromString(segment))
    def /(names: String*): Namespace          = Namespace(path ++ Path.fromIterable(names.map(Name.fromString(_))))
    def /(names: Iterable[String]): Namespace = Namespace(path ++ Path.fromIterable(names.map(Name.fromString(_))))

    @inline def toPath: Path                                            = path
    def parts(implicit renderer: NamespaceRenderer): IndexedSeq[String] = path.parts(renderer)

    def render(implicit renderer: NamespaceRenderer): String = renderer(path)
    /// An alias for `render`
    def show(implicit renderer: NamespaceRenderer): String = render
    def toModuleName: ModuleName                           = ModuleName(path)

    override def toString(): String = render
  }

  object Namespace {
    val ns: Namespace = Namespace(Path.empty)

    def apply(parts: Name*): Namespace                    = Namespace(Path.fromIterable(parts))
    def fromIterable(segments: Iterable[Name]): Namespace = Namespace(Path.fromIterable(segments))
    def fromModuleName(moduleName: ModuleName): Namespace = Namespace(moduleName.path)
    def fromStrings(parts: String*): Namespace            = Namespace(Path.fromStrings(parts: _*))

    def fromPath(path: Path): Namespace = Namespace(path)

  }

  sealed case class NamespaceRenderer(separator: String, nameRenderer: NameRenderer) extends (Path => String) {
    def apply(path: Path): String        = path.toString(nameRenderer, separator)
    final def render(path: Path): String = apply(path)
  }

  object NamespaceRenderer {
    val CamelCase: NamespaceRenderer = NamespaceRenderer(".", NameRenderer.CamelCase)
    val KebabCase: NamespaceRenderer = NamespaceRenderer(".", NameRenderer.KebabCase)
    val SnakeCase: NamespaceRenderer = NamespaceRenderer(".", NameRenderer.SnakeCase)
    val TitleCase: NamespaceRenderer = NamespaceRenderer(".", NameRenderer.TitleCase)

    implicit val default: NamespaceRenderer = TitleCase
    implicit def toPathRenderer(renderer: NamespaceRenderer): PathRenderer =
      PathRenderer(renderer.separator, renderer.nameRenderer)
  }
}
