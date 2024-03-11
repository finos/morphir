[<AutoOpen>]
module Morphir.Extensions.Strings

open System

let (|NullOrEmptyString|_|) (s: string) =
    if String.IsNullOrEmpty(s) then None else Some s

let (|NullOrWhiteSpaceString|_|) (s: string) =
    if String.IsNullOrWhiteSpace(s) then Some() else None

let (|NullString|EmptyString|WhiteSpaceOnlyString|StringWithContent|) (s: string) =
    if isNull s then
        NullString
    else if String.IsNullOrEmpty s then
        EmptyString
    else if String.IsNullOrWhiteSpace s then
        WhiteSpaceOnlyString s
    else
        StringWithContent s

type String with

    static member HasContent(s: string) = not (String.IsNullOrWhiteSpace s)
    static member ToUpper(s: string) = s.ToUpper()

    static member ToUpperInvariant(s: string) = s.ToUpperInvariant()
