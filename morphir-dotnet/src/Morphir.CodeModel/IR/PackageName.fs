module Morphir.IR.PackageName

open Morphir.IR
open Morphir.IR.Path

/// A package name is a globally unique identifier for a package. It is represented by a path, which
/// is a list of names.
[<Struct>]
type PackageName =
    | PackageName of UnderlyingPath: Path

    static member FromString(packagePath: string) =
        PackageName(Path.fromString packagePath)

/// Create a package name from a path.
let fromPath path = PackageName path

/// Get the underlying path from a package name.
let toPath (PackageName path) = path

let inline fromString packagePath = PackageName.FromString packagePath
