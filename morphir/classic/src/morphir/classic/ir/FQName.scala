package morphir.classic.ir

final case class FQName(packageName: PackageName, moduleName: ModuleName, localName: Name)
object FQName