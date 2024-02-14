namespace Morphir.IR

type Name =
    | Name of string list

    static let fromList (segments: string list) = Name segments

type Path = Path of Name list

type QName = QName of Path * Name

type PackageName = PackageName of Path

type ModuleName = ModuleName of Path
