package org.finos.morphir.ir.gen1

trait NamingOptionsModule { self: PackageNameModule with ModuleNameModule =>

  sealed case class FQNamingOptions(defaultPackage: PackageName, defaultModule: ModuleName, defaultSeparator: String)

  object FQNamingOptions {
    implicit val default: FQNamingOptions =
      FQNamingOptions(PackageName.empty, ModuleName.empty, ":")
  }
}
