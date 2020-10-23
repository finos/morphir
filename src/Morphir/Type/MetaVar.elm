module Morphir.Type.MetaVar exposing (..)

import Morphir.IR.Name exposing (Name)


type alias Variable =
    ( Int, Int )


variable : Int -> Variable
variable i =
    ( i, 0 )


subVariable : Variable -> Variable
subVariable ( i, s ) =
    ( i, s + 1 )


toName : Variable -> Name
toName ( i, s ) =
    [ "t", String.fromInt i, String.fromInt s ]
