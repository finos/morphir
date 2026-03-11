package morphir.classic.ir

import neotype.*

type ModuleName = ModuleName.Type
object ModuleName extends Subtype[Path]

final case class QualifiedModuleName(packageName: PackageName, moduleName: ModuleName)