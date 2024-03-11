module Morphir.Utils.StringTests

open System
open Morphir.Extensions.Strings
open FsCheck.Xunit

[<Property>]
let ``The active pattern for (|NullString|EmptyString|WhitespaceOnlyString|StringWithContent|) should work as expected``
    (input: string)
    =
    match input with
    | NullString -> isNull input
    | EmptyString -> input = String.Empty
    | WhiteSpaceOnlyString s -> s.Length > 0 && s.Trim().Length = 0
    | StringWithContent s -> not (isNull s) && s.Trim().Length > 0

[<Property>]
let ``HasContent should be true if the string is not null, has a length greater than 0, and is not all whitespace``
    (input: string)
    =
    match String.HasContent input with
    | true -> not (isNull input) && input.Trim().Length > 0
    | false -> isNull input || input.Trim().Length = 0
