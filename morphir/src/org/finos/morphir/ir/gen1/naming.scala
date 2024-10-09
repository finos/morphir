package org.finos.morphir.ir.gen1

object naming {

  final implicit class PackageNameSyntax(val self: PackageName) extends AnyVal {
    def /(moduleName: ModuleName): QualifiedModuleName = QualifiedModuleName(self, moduleName)
  }

  final implicit class QualifiedModuleNameSyntax(val self: QualifiedModuleName) extends AnyVal {
    def %(localName: String): FQName = FQName(self.packageName, self.modulePath, Name.fromString(localName))
    def %(name: Name): FQName        = FQName(self.packageName, self.modulePath, name)
  }

  final implicit class NamingHelper(val sc: StringContext) extends AnyVal {

    def fqn(args: Any*): FQName = {
      val interlaced = interlace(sc.parts, args.map(_.toString))
      FQName.fromString(interlaced.mkString)
    }

    def mod(args: Any*): ModuleName = {
      val interlaced = interlace(sc.parts, args.map(_.toString))
      ModuleName.fromString(interlaced.mkString)
    }

    def n(args: Any*): Name = {
      val interlaced = interlace(sc.parts, args.map(_.toString))
      Name.fromString(interlaced.mkString)
    }

    def qmn(args: Any*): QualifiedModuleName = {
      val interlaced = interlace(sc.parts, args.map(_.toString))
      QualifiedModuleName.fromString(interlaced.mkString)
    }

    def name(args: Any*): Name = {
      val interlaced = interlace(sc.parts, args.map(_.toString))
      Name.fromString(interlaced.mkString)
    }

    def pkg(args: Any*): PackageName = {
      val interlaced = interlace(sc.parts, args.map(_.toString))
      PackageName.fromString(interlaced.mkString)
    }

    def path(args: Any*): Path = {
      val interlaced = interlace(sc.parts, args.map(_.toString))
      Path.fromString(interlaced.mkString)
    }
  }

  private[morphir] def interlace[T](a: Iterable[T], b: Iterable[T]): List[T] =
    if (a.isEmpty) b.toList
    else a.head +: interlace(b, a.tail)
}
