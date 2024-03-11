module Morphir.SDK.Array

open Morphir.SDK.List
open Morphir.SDK.Maybe

type Array<'a> = 'a array

let empty: Array<'a> = [||]

let inline fromList (lst: List<'a>) : Array<'a> = Array.ofList lst

let inline isEmpty (arr: Array<'a>) : bool = Array.isEmpty arr
let inline length (arr: Array<'a>) : int = Array.length arr

let get index arr : Maybe<'a> =
    arr
    |> Array.tryItem index
    |> Maybe.Conversions.Options.optionsToMaybe
