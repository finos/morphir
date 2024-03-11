module Morphir.Pattern

open Morphir.SDK.Maybe
open Morphir.SDK

type Pattern<'a, 'b> = 'a -> Maybe<'b>

/// Create a new pattern by applying a function to the pattern's result
let map (f: 'b -> 'a) (pattern: Pattern<'a, 'b>) (a: 'a) : Maybe<'a> =
    pattern a
    |> Maybe.map f

let matchAny a = Just a

let matchValue a b = if (a = b) then Just a else Nothing

let matchList matchItems listToMatch =
    if ((List.length matchItems) = (List.length listToMatch)) then
        let matchingItems =
            List.map2 (fun matchItem item -> matchItem item) matchItems listToMatch

        if
            matchingItems
            |> List.any Maybe.isNothing
        then
            Nothing

        else
            Just(
                matchingItems
                |> List.filterMap identity
            )

    else
        Nothing
