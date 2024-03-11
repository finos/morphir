namespace Morphir.IR

open Morphir.IR.Name
open Morphir.IR.Path


type QName = QName of Path * Name

type PackageName = PackageName of Path

type ModuleName = ModuleName of Path
