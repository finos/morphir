module Morphir.Type.MetaVar exposing (..)

import Morphir.IR.Name exposing (Name)


type alias Variable =
    ( Int, Int )


variable : Int -> Variable
variable i =
    ( i, 0 )


toName : Variable -> Name
toName ( i, s ) =
    [ "t", String.fromInt i, String.fromInt s ]
