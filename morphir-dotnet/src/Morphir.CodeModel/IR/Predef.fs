[<AutoOpen>]
module Morphir.IR.Predef

open Morphir.IR
open Morphir.IR.Name
open Morphir.IR.Path

let (|NameParts|) (Name parts) = parts

let (|PathSegments|) (Path path) = path |> List.map Name.toList

let name = NameBuilder()
let path = PathBuilder()

let mkName parts = Name.fromList parts

let mkPathWith (toName: string list -> Name.Name) (parts: string list list) : Path.Path =
    parts |> List.map toName |> Path.fromList

let mkPath (parts: string list list) : Path.Path = mkPathWith Name.fromList parts

let mkPathCanonical (parts: string list list) : Path.Path =
    let toName segments =
        segments |> List.map Name.partsFromString |> List.concat |> Name.fromList

    mkPathWith toName parts

let toUnit (_: 'a) : unit = ()
