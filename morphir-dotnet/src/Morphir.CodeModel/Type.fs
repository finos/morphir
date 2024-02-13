namespace Morphir.CodeModel

type Name = Name of string

type Type =
    | Variable of Name
    | Tuple of Type list
    static let (|Unit|_|) = function
        | Tuple [] -> Some ()
        | _ -> None
    static member Unit: Type = Tuple []

module IntrinsicType =
    let unit = Tuple []