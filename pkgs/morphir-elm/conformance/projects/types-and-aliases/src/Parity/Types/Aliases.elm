module Parity.Types.Aliases exposing
    ( Point, Labeled, Pair, Triple, Handler, Box, Scalars, Table
    , origin, label
    )

{-| Aliases of every type form.

The second paragraph.
-}

import Dict exposing (Dict)
import Set exposing (Set)


{-| A record. -}
type alias Point =
    { x : Float, y : Float }


{-| An extensible
record.
-}
type alias Labeled a =
    { a | label : String }


type alias Pair a b =
    ( a, b )


type alias Triple =
    ( Int, Char, () )


type alias Handler a =
    a -> Maybe a -> Result String a


type alias Box a =
    { value : a, items : List a }


type alias Scalars =
    { int : Int, float : Float, text : String, char : Char, flag : Bool }


type alias Table k v =
    Dict k (Set v)


origin : Point
origin =
    { x = 0, y = 0 }


label : Labeled a -> String
label record =
    record.label
