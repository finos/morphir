package org.finos.morphir.ir.gen1

/// A qualified module name is a globally unique identifier for a module. It is represented by the combination of a package name and the module name.
sealed case class QualifiedModuleName(packageName: PackageName, modulePath: ModuleName) { self =>
  def /(moduleName: ModuleName): QualifiedModuleName =
    QualifiedModuleName(self.packageName, modulePath) // ++ moduleName)
  def /(namespaceAddition: String): QualifiedModuleName =
    QualifiedModuleName(self.packageName, modulePath.addPart(namespaceAddition))

  def toTuple: (Path, Path) = (packageName.toPath, modulePath.toPath)

  override def toString: String = Array(
    Path.toString(Name.toTitleCase, ".", packageName.toPath),
    Path.toString(Name.toTitleCase, ".", modulePath.toPath)
  ).mkString(":")
}

object QualifiedModuleName {
  val empty: QualifiedModuleName = QualifiedModuleName(PackageName.empty, ModuleName.empty)

  def apply(modulePath: String)(implicit packageName: PackageName): QualifiedModuleName =
    QualifiedModuleName(packageName, ModuleName.fromString(modulePath))

  /** Parse a string into a QualifedModuleName using splitter as the separator between package, and module */
  def fromString(nameString: String, splitter: String)(implicit options: FQNamingOptions): QualifiedModuleName =
    nameString.split(splitter) match {
      case Array(moduleNameString, localNameString) =>
        qmn(moduleNameString, localNameString)
      case Array(localNameString) =>
        qmn(localNameString)
      case _ => throw QualifiedModuleNameParsingError(nameString)
    }

  def fromString(fqNameString: String)(implicit options: FQNamingOptions): QualifiedModuleName =
    fromString(fqNameString, options.defaultSeparator)

  /** Convenience function to create a fully-qualified name from 2 strings with default package name */
  def qmn(packageName: String, moduleName: String): QualifiedModuleName =
    QualifiedModuleName(PackageName.fromString(packageName), ModuleName(Path.fromString(moduleName)))

  /** Convenience function to create a fully-qualified name from 1 string with defaults for package and module */
  def qmn(moduleName: String)(implicit options: FQNamingOptions): QualifiedModuleName =
    QualifiedModuleName(options.defaultPackage, ModuleName(Path.fromString(moduleName)))

  object AsTuple {
    def unapply(name: QualifiedModuleName): Option[(Path, Path)] =
      Some(name.toTuple)
  }
}

sealed case class QualifiedModuleNameParsingError(invalidName: String)
    extends Exception(s"Unable to parse: [$invalidName] into a valid QualifiedModuleName")
